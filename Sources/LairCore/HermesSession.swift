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
        /// Extra headers, for when Hermes sits behind a proxy that wants its own token.
        public var headers: [String: String]

        public init(apiKey: String, headers: [String: String] = [:]) {
            self.apiKey = apiKey
            self.headers = headers
        }
    }

    public enum Failure: LocalizedError, Equatable {
        case status(Int)
        case reply(String)
        /// The history came back as something other than Hermes's JSON, such as a proxy's page.
        case history

        public var errorDescription: String? {
            switch self {
            case .status(let code): "Hermes answered HTTP \(code)."
            case .reply(let reason): "Hermes stopped the reply (\(reason))."
            case .history: "Hermes's session history wasn't JSON."
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
    public let problems: AsyncStream<String>
    private let problemsContinuation: AsyncStream<String>.Continuation
    private let credentials: Credentials
    private let model: Mutex<String>
    private let systemPrompt: String
    private let sessionID = "lair-\(UUID().uuidString.lowercased())"
    private let currentTurn = Mutex<Task<Void, Never>?>(nil)

    public init(baseURL: URL, credentials: Credentials, model: String? = nil, systemPrompt: String = VoicePrompt.text,
                poll: Duration = delegationPoll) {
        self.baseURL = baseURL
        self.poll = poll
        (news, newsContinuation) = AsyncStream<String>.makeStream()
        (problems, problemsContinuation) = AsyncStream<String>.makeStream()
        endpoint = baseURL.appending(path: "v1/chat/completions")
        self.credentials = credentials
        self.model = Mutex(model ?? "hermes-agent")
        self.systemPrompt = systemPrompt
    }

    public func ask(_ text: String) throws -> AsyncThrowingStream<AgentReply, Error> {
        let request = try request(for: text)
        let (reply, continuation) = AsyncThrowingStream<AgentReply, Error>.makeStream()
        let turn = Task {
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request, delegate: NoRedirects.shared)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard status == 200 else { throw Failure.status(status) }
                var stream = ChatCompletionStream()
                reading: for try await line in bytes.lines {
                    switch stream.feed(line) {
                    case .text(let text): continuation.yield(.text(text))
                    case .toolStarted(let tool):
                        if tool == "delegate_task" { delegations.withLock { $0.pending += 1 } }
                        continuation.yield(.activity(.toolStarted(id: UUID().uuidString, name: tool, input: "")))
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

    public func setModel(_ model: String) throws {
        self.model.withLock { $0 = model }
    }

    public func interrupt() {
        currentTurn.withLock { $0?.cancel() }
    }

    public func stop() {
        interrupt()
        delegations.withLock { $0.watcher?.cancel() }
        newsContinuation.finish()
        problemsContinuation.finish()
    }

    private func watchDelegations() {
        delegations.withLock { state in
            guard state.pending > 0, state.watcher == nil else { return }
            state.watcher = Task { [self] in
                defer { delegations.withLock { $0.watcher = nil } }
                let deadline = ContinuousClock.now + Self.delegationWatch
                var failing = false
                while ContinuousClock.now < deadline, !Task.isCancelled {
                    try? await Task.sleep(for: poll)
                    let results: [(id: String, text: String)]
                    do {
                        results = try await delegationResults()
                        failing = false
                    } catch {
                        // Once per failure streak: the check keeps trying, and a lasting failure isn't repeated.
                        if !failing, !Task.isCancelled {
                            problemsContinuation.yield("Can't check on background work: \(error.localizedDescription)")
                        }
                        failing = true
                        continue
                    }
                    for result in results {
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

    private func delegationResults() async throws -> [(id: String, text: String)] {
        var components = URLComponents(url: baseURL.appending(path: "api/sessions/\(sessionID)/messages"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [.init(name: "order", value: "latest"), .init(name: "limit", value: "50")]
        var request = URLRequest(url: components.url!)
        authorize(&request)
        let (data, response) = try await URLSession.shared.data(for: request, delegate: NoRedirects.shared)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Failure.status(status) }
        return try Self.delegationResults(in: data)
    }

    /// Background results are stored as user messages that open with this marker.
    static func delegationResults(in data: Data) throws -> [(id: String, text: String)] {
        guard let page = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let messages = page["data"] as? [[String: Any]]
        else { throw Failure.history }
        return messages.compactMap { message in
            guard message["role"] as? String == "user", let text = message["content"] as? String,
                  text.hasPrefix("[ASYNC DELEGATION BATCH COMPLETE"), let id = message["id"]
            else { return nil }
            return ("\(id)", text)
        }
    }

    private func authorize(_ request: inout URLRequest) {
        request.setValue("Bearer \(credentials.apiKey)", forHTTPHeaderField: "Authorization")
        for (name, value) in credentials.headers { request.setValue(value, forHTTPHeaderField: name) }
    }

    func request(for text: String) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authorize(&request)
        request.setValue(sessionID, forHTTPHeaderField: "X-Hermes-Session-Id")
        // With a session id Hermes loads the history itself, so only the new turn is sent.
        let body: [String: Any] = [
            "model": model.withLock { $0 },
            "stream": true,
            "messages": [["role": "system", "content": systemPrompt], ["role": "user", "content": text]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}

/// Hermes never redirects; a redirect comes from something in front of it, usually a login page, and following it
/// would read that page as Hermes's answer.
private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    static let shared = NoRedirects()

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? { nil }
}
