import Foundation
import Synchronization

/// A call with a Hermes agent over its OpenAI-compatible API. Hermes keeps the history server-side,
/// keyed by a session id that is new for every call.
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

    private let endpoint: URL
    private let credentials: Credentials
    private let model: String
    private let systemPrompt: String
    private let sessionID = "lair-\(UUID().uuidString.lowercased())"
    private let currentTurn = Mutex<Task<Void, Never>?>(nil)

    public init(baseURL: URL, credentials: Credentials, model: String? = nil, systemPrompt: String = VoicePrompt.text) {
        endpoint = baseURL.appending(path: "v1/chat/completions")
        self.credentials = credentials
        self.model = model ?? "hermes-agent"
        self.systemPrompt = systemPrompt
    }

    public func ask(_ text: String) throws -> AsyncThrowingStream<String, Error> {
        let request = try request(for: text)
        let (reply, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        let turn = Task {
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard status == 200 else { throw Failure.status(status) }
                var stream = ChatCompletionStream()
                reading: for try await line in bytes.lines {
                    switch stream.feed(line) {
                    case .text(let text): continuation.yield(text)
                    case .done: break reading
                    case .failed(let reason): throw Failure.reply(reason)
                    case nil: break
                    }
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in turn.cancel() }
        currentTurn.withLock { $0 = turn }
        return reply
    }

    public func stop() {
        currentTurn.withLock { $0?.cancel() }
    }

    func request(for text: String) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(credentials.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(sessionID, forHTTPHeaderField: "X-Hermes-Session-Id")
        request.setValue(credentials.accessClientID, forHTTPHeaderField: "CF-Access-Client-Id")
        request.setValue(credentials.accessClientSecret, forHTTPHeaderField: "CF-Access-Client-Secret")
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
