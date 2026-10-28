import Foundation
import Synchronization

/// A call with a Hermes agent over its OpenAI-compatible API. Hermes keeps the history server-side,
/// keyed by a session id that is new for every call.
///
/// Work Hermes hands to a background subagent ends the turn early; its result lands in the session history later
/// and never starts a turn by itself. So after a turn that delegated, the history is watched and each result
/// is reported on `news`.
public final class HermesSession: AgentSession {
    public struct Credentials: Sendable {
        public var apiKey: String
        /// Cloudflare Access service token, for when Hermes sits behind Access.
        public var accessClientID: String?
        public var accessClientSecret: String?

        public init(apiKey: String, accessClientID: String? = nil, accessClientSecret: String? = nil) {
            self.apiKey = apiKey
            self.accessClientID = accessClientID
            self.accessClientSecret = accessClientSecret
        }
    }

    public enum Failure: LocalizedError {
        case status(Int)
        case reply(String)

        public var errorDescription: String? {
            switch self {
            case .status(let code): "Hermes answered HTTP \(code)."
            case .reply(let reason): "Hermes stopped the reply (\(reason))."
            }
        }
    }

    /// How often the history is checked, and for how long, while background work is out.
    public static let delegationPoll = Duration.seconds(4)
    public static let delegationWatch = Duration.seconds(30 * 60)

    private struct Delegations {
        var pending = 0
        var reported: Set<String> = []
        var watcher: Task<Void, Never>?
    }

    private let baseURL: URL
    private let endpoint: URL
    private let poll: Duration
    private let delegations = Mutex(Delegations())
    public let news: AsyncStream<String>
    private let newsContinuation: AsyncStream<String>.Continuation
    private let credentials: Credentials
    private let model: String
    private let systemPrompt: String
    private let sessionID = "lair-\(UUID().uuidString.lowercased())"
    private let currentTurn = Mutex<Task<Void, Never>?>(nil)

    public init(baseURL: URL, credentials: Credentials, model: String? = nil, systemPrompt: String = VoicePrompt.text,
                poll: Duration = delegationPoll) {
        self.baseURL = baseURL
        self.poll = poll
        (news, newsContinuation) = AsyncStream<String>.makeStream()
        endpoint = baseURL.appending(path: "v1/chat/completions")
        self.credentials = credentials
        self.model = model ?? "hermes-agent"
        self.systemPrompt = systemPrompt
    }

    public func ask(_ text: String) throws -> AsyncThrowingStream<AgentReply, Error> {
        let request = try request(for: text)
        let (reply, continuation) = AsyncThrowingStream<AgentReply, Error>.makeStream()
        let turn = Task {
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard status == 200 else { throw Failure.status(status) }
                var stream = ChatCompletionStream()
                reading: for try await line in bytes.lines {
                    switch stream.feed(line) {
                    case .text(let text): continuation.yield(.text(text))
                    case .toolStarted("delegate_task"): delegations.withLock { $0.pending += 1 }
                    case .toolStarted: break
                    case .done: break reading
                    case .failed(let reason): throw Failure.reply(reason)
                    case nil: break
                    }
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
            watchDelegations()
        }
        continuation.onTermination = { _ in turn.cancel() }
        currentTurn.withLock { $0 = turn }
        return reply
    }

    public func interrupt() {
        currentTurn.withLock { $0?.cancel() }
    }

    public func stop() {
        interrupt()
        delegations.withLock { $0.watcher?.cancel() }
        newsContinuation.finish()
    }

    private func watchDelegations() {
        delegations.withLock { state in
            guard state.pending > 0, state.watcher == nil else { return }
            state.watcher = Task { [self] in
                defer { delegations.withLock { $0.watcher = nil } }
                let deadline = ContinuousClock.now + Self.delegationWatch
                while ContinuousClock.now < deadline, !Task.isCancelled {
                    try? await Task.sleep(for: poll)
                    for result in await delegationResults() {
                        let isNew = delegations.withLock { state in
                            guard state.reported.insert(result.id).inserted else { return false }
                            state.pending = max(0, state.pending - 1)
                            return true
                        }
                        if isNew { newsContinuation.yield(result.text) }
                    }
                    if delegations.withLock({ $0.pending == 0 }) { return }
                }
            }
        }
    }

    private func delegationResults() async -> [(id: String, text: String)] {
        var components = URLComponents(url: baseURL.appending(path: "api/sessions/\(sessionID)/messages"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [.init(name: "order", value: "latest"), .init(name: "limit", value: "50")]
        var request = URLRequest(url: components.url!)
        authorize(&request)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return [] }
        return Self.delegationResults(in: data)
    }

    /// Background results are stored as user messages that open with this marker.
    static func delegationResults(in data: Data) -> [(id: String, text: String)] {
        let page = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let messages = page?["data"] as? [[String: Any]] ?? []
        return messages.compactMap { message in
            guard message["role"] as? String == "user", let text = message["content"] as? String,
                  text.hasPrefix("[ASYNC DELEGATION BATCH COMPLETE"), let id = message["id"]
            else { return nil }
            return ("\(id)", text)
        }
    }

    private func authorize(_ request: inout URLRequest) {
        request.setValue("Bearer \(credentials.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(credentials.accessClientID, forHTTPHeaderField: "CF-Access-Client-Id")
        request.setValue(credentials.accessClientSecret, forHTTPHeaderField: "CF-Access-Client-Secret")
    }

    func request(for text: String) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authorize(&request)
        request.setValue(sessionID, forHTTPHeaderField: "X-Hermes-Session-Id")
        // With a session id Hermes loads the history itself, so only the new turn is sent.
        let body: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": [["role": "system", "content": systemPrompt], ["role": "user", "content": text]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}
