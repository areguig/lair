import Foundation
import LairCore
import Synchronization

/// A JSON-RPC request id: the peer may use numbers or strings, and its answer must carry the same one back.
public enum JSONRPCID: Hashable, Sendable, Codable, CustomStringConvertible {
    case number(Int)
    case string(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Int.self) { self = .number(number) } else { self = .string(try container.decode(String.self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .number(let number): try container.encode(number)
        case .string(let string): try container.encode(string)
        }
    }

    public var description: String {
        switch self {
        case .number(let number): "\(number)"
        case .string(let string): string
        }
    }
}

/// An error the peer answered with.
public struct JSONRPCError: LocalizedError, Equatable, Codable {
    public let code: Int
    public let message: String

    public var errorDescription: String? { message }

    public static func methodNotFound(_ method: String) -> JSONRPCError {
        JSONRPCError(code: -32601, message: "Method not found: \(method)")
    }
}

/// JSON-RPC 2.0, one message per line, both ways. Everything the peer sends is handled in the order it arrives,
/// on one reader: answers to our requests run their completion, and the peer's own requests and notifications go
/// to `handle`. So an answer never overtakes what the peer sent before it.
public final class JSONRPCPeer: Sendable {
    public enum Incoming: Sendable {
        case request(id: JSONRPCID, method: String, params: Data)
        case notification(method: String, params: Data)
    }

    public typealias Completion = @Sendable (Result<Data, Error>) -> Void

    private let channel: LineChannel
    private let state = Mutex(State())

    private struct State {
        var nextID = 1
        var waiting: [Int: Completion] = [:]
        var closed = false
    }

    public init(channel: LineChannel) {
        self.channel = channel
    }

    /// Starts reading; `closed` runs once the peer has gone, after every request still waiting has failed.
    public func start(handle: @escaping @Sendable (Incoming) -> Void, closed: @escaping @Sendable () -> Void) {
        Task { [self] in
            do {
                for try await line in channel.lines { receive(line, handle: handle) }
            } catch {}
            let waiting = state.withLock { state in
                state.closed = true
                defer { state.waiting = [:] }
                return Array(state.waiting.values)
            }
            for completion in waiting { completion(.failure(AgentStopped())) }
            closed()
        }
    }

    /// Sends a request; `completion` gets the raw result in reading order, before anything the peer sends after it.
    public func request(_ method: String, _ params: some Encodable, completion: @escaping Completion) {
        let id: Int? = state.withLock { state in
            guard !state.closed else { return nil }
            defer { state.nextID += 1 }
            state.waiting[state.nextID] = completion
            return state.nextID
        }
        guard let id else { return completion(.failure(AgentStopped())) }
        do {
            try channel.send(JSONEncoder().encode(Outgoing(id: .number(id), method: method, params: params)))
        } catch {
            state.withLock { $0.waiting.removeValue(forKey: id) }?(.failure(error))
        }
    }

    /// Sends a request and returns its result, decoded.
    public func request<Result: Decodable>(_ method: String, _ params: some Encodable,
                                           as: Result.Type = Result.self) async throws -> Result {
        let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            request(method, params) { continuation.resume(with: $0) }
        }
        return try JSONDecoder().decode(Result.self, from: data)
    }

    public func notify(_ method: String, _ params: some Encodable) throws {
        try channel.send(JSONEncoder().encode(Outgoing(id: nil, method: method, params: params)))
    }

    public func respond(to id: JSONRPCID, with result: some Encodable) throws {
        try channel.send(JSONEncoder().encode(Answer(id: id, result: result, error: nil)))
    }

    public func respond(to id: JSONRPCID, with error: JSONRPCError) throws {
        try channel.send(JSONEncoder().encode(Answer<Empty>(id: id, result: nil, error: error)))
    }

    private func receive(_ line: Data, handle: (Incoming) -> Void) {
        guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
        let params = Self.data(message["params"])
        if let method = message["method"] as? String {
            if let id = Self.id(message["id"]) {
                handle(.request(id: id, method: method, params: params))
            } else {
                handle(.notification(method: method, params: params))
            }
            return
        }
        guard case .number(let id) = Self.id(message["id"]),
              let completion = state.withLock({ $0.waiting.removeValue(forKey: id) })
        else { return }
        if let error = message["error"], let decoded = try? JSONDecoder().decode(JSONRPCError.self, from: Self.data(error)) {
            completion(.failure(decoded))
        } else {
            completion(.success(Self.data(message["result"])))
        }
    }

    private static func id(_ value: Any?) -> JSONRPCID? {
        switch value {
        case let number as Int: .number(number)
        case let string as String: .string(string)
        default: nil
        }
    }

    /// A part of a message, back as JSON for its own decoder; absent or null becomes `{}`.
    private static func data(_ value: Any?) -> Data {
        guard let value, !(value is NSNull) else { return Data("{}".utf8) }
        return (try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])) ?? Data("{}".utf8)
    }

    private struct Outgoing<Params: Encodable>: Encodable {
        let jsonrpc = "2.0"
        let id: JSONRPCID?
        let method: String
        let params: Params
    }

    private struct Answer<Result: Encodable>: Encodable {
        let jsonrpc = "2.0"
        let id: JSONRPCID
        let result: Result?
        let error: JSONRPCError?
    }

    private struct Empty: Encodable {}
}
