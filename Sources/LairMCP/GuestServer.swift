import Foundation
import Hummingbird
import MCP
import Synchronization

/// An agent connected over MCP: one per session, so two terminals running Claude Code are two guests.
public struct Guest: Hashable, Sendable {
    public let id: String
    public let name: String
    /// The client as it names itself, such as `claude-code`: which tool this is.
    public let client: String?
    /// The agent's working folder, from its MCP roots, once it said.
    public let folder: URL?

    public init(id: String, name: String, client: String? = nil, folder: URL? = nil) {
        self.id = id
        self.name = name
        self.client = client
        self.folder = folder
    }

    /// `/mcp/Atlas` names the guest; otherwise the client's own name, said the way people say it.
    static func name(path: String?, client: Client.Info?) -> String {
        if let path, !path.isEmpty { return path }
        switch client?.name {
        case "claude-code": return "Claude Code"
        case "omp-coding-agent": return "omp"
        case nil: return "Guest"
        case let name?: return client?.title ?? name
        }
    }
}

/// What a guest can do in the room. It talks to you; you don't start its turns.
public protocol GuestHost: Sendable {
    func speak(_ text: String, from guest: Guest) async
    /// Your answer, or nil if you didn't give one: one of `choices` when it picks one. Cancelled when the agent stops
    /// waiting.
    func ask(_ question: String, choices: [String], from guest: Guest) async -> String?
    func left(_ guest: Guest) async
}

/// Any agent on this Mac reaches you at `http://127.0.0.1:<port>/mcp`, with Lair's token as a bearer token.
/// One MCP server per session, since an MCP server is initialized once per client.
public actor GuestServer {
    static let instructions = """
        Lair is the user's voice link: they hear what you send through it, even away from the screen. \
        Call `speak` when you finish a task that took a while, when you're blocked, or when something needs their \
        attention, in one or two plain sentences. Call `ask` when you need their decision to go on, instead of \
        stopping and waiting in the terminal. Never put code, paths or markdown in what you say.
        """

    static let tools = [
        Tool(name: "speak",
             description: """
                 Say something to the user out loud, through Lair. Use it for short updates they should hear \
                 even when they aren't looking: done, blocked, a result. One or two plain sentences, no markdown, \
                 no paths or code.
                 """,
             inputSchema: .object([
                 "type": "object",
                 "properties": .object(["text": .object(["type": "string", "description": "What to say."])]),
                 "required": .array(["text"]),
             ])),
        Tool(name: "ask",
             description: """
                 Ask the user a question out loud, through Lair, and get their answer as text, spoken or typed. Use \
                 it when you need a decision to go on. One short question that can't be answered with a bare yes. \
                 For a choice, pass the options in `choices` (two to five, a few words each): they're read out and \
                 shown as buttons, and you get back the one picked, or the user's own words if they said something \
                 else. If they don't answer, carry on with what's safe or ask again later.
                 """,
             inputSchema: .object([
                 "type": "object",
                 "properties": .object([
                     "question": .object(["type": "string", "description": "The question."]),
                     "choices": .object([
                         "type": "array", "items": .object(["type": "string"]),
                         "description": "The options to pick from, if it's a choice.",
                     ]),
                 ]),
                 "required": .array(["question"]),
             ])),
    ]

    private struct Session {
        let server: Server
        let transport: StatefulHTTPServerTransport
        var guest: Guest
        /// Server requests only reach the client over its GET stream; one sent before it opens is lost.
        var streamOpen = false
        var askedFolder = false
    }

    private let host: any GuestHost
    private let token: String
    private var sessions: [String: Session] = [:]

    public init(host: any GuestHost, token: String) {
        self.host = host
        self.token = token
    }

    /// Serves until cancelled; only this Mac can connect.
    public func run(port: Int) async throws {
        let router = Router()
        for path in ["mcp", "mcp/:guest"] {
            for method in [HTTPRequest.Method.post, .get, .delete] {
                router.on(RouterPath(path), method: method) { try await self.respond(to: $0, context: $1) }
            }
        }
        let app = Application(router: router, configuration: .init(address: .hostname("127.0.0.1", port: port)))
        try await app.runService(gracefulShutdownSignals: [])
    }

    private func respond(to request: Request, context: BasicRequestContext) async throws -> Response {
        let body = try await request.body.collect(upTo: 1 << 20)
        var headers: [String: String] = [:]
        for field in request.headers { headers[field.name.rawName] = field.value }
        let mcpRequest = MCP.HTTPRequest(method: request.method.rawValue, headers: headers,
                                         body: body.readableBytes > 0 ? Data(buffer: body) : nil, path: request.uri.path)
        return Self.response(from: await handle(mcpRequest, path: context.parameters.get("guest")))
    }

    func handle(_ request: MCP.HTTPRequest, path: String?) async -> MCP.HTTPResponse {
        guard request.header("Authorization") == "Bearer \(token)" else {
            return .error(statusCode: 401, .invalidRequest("Lair needs its token: connect this agent from Lair's Settings"))
        }
        if let id = request.header(HTTPHeaderName.sessionID), let session = sessions[id] {
            let response = await session.transport.handleRequest(request)
            if request.method == "DELETE", response.statusCode == 200 { await end(id) }
            if request.method == "GET", case .stream = response { sessions[id]?.streamOpen = true }
            return response
        }
        guard request.method == "POST", let body = request.body,
              (try? JSONDecoder().decode(Method.self, from: body))?.method == "initialize"
        else { return .error(statusCode: 404, .invalidRequest("Session not found; initialize first")) }
        let id = UUID().uuidString
        let transport = StatefulHTTPServerTransport(sessionIDGenerator: FixedID(id: id))
        let server = Server(name: "lair", version: "1", instructions: Self.instructions, capabilities: .init(tools: .init()))
        await register(server, session: id)
        sessions[id] = Session(server: server, transport: transport, guest: Guest(id: id, name: Guest.name(path: path, client: nil)))
        do {
            try await server.start(transport: transport) { client, _ in
                await self.named(id, path: path, client: client)
            }
        } catch {
            sessions[id] = nil
            return .error(statusCode: 500, .internalError(error.localizedDescription))
        }
        return await transport.handleRequest(request)
    }

    private func named(_ id: String, path: String?, client: Client.Info) {
        sessions[id]?.guest = Guest(id: id, name: Guest.name(path: path, client: client), client: client.name)
    }

    private func end(_ id: String) async {
        guard let session = sessions.removeValue(forKey: id) else { return }
        await host.left(session.guest)
    }

    /// The guest, its folder asked for once, on its first tool call: agents open their stream when they start,
    /// so it's open by then. Waits on the client at most briefly.
    private func guest(_ id: String) async -> Guest? {
        guard let session = sessions[id] else { return nil }
        guard session.streamOpen, !session.askedFolder else { return session.guest }
        sessions[id]?.askedFolder = true
        let roots = await Self.within(.seconds(2)) { try await session.server.listRoots() }
        sessions[id]?.guest = Guest(id: id, name: session.guest.name, client: session.guest.client,
                                    folder: roots.flatMap(Self.folder))
        return sessions[id]?.guest
    }

    private func register(_ server: Server, session id: String) async {
        let host = host
        await server.withMethodHandler(ListTools.self) { _ in .init(tools: Self.tools) }
        await server.withMethodHandler(CallTool.self) { [weak self] params in
            guard let self, let guest = await self.guest(id) else { throw MCPError.internalError("Session ended") }
            let argument = { (name: String) in
                (params.arguments?[name]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            switch params.name {
            case "speak":
                guard !argument("text").isEmpty else { return .init(content: [.text("Nothing to say.")], isError: true) }
                await host.speak(argument("text"), from: guest)
                return .init(content: [.text("Said.")], isError: false)
            case "ask":
                guard !argument("question").isEmpty else { return .init(content: [.text("No question.")], isError: true) }
                let choices = (params.arguments?["choices"]?.arrayValue ?? []).compactMap(\.stringValue)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                guard let answer = await host.ask(argument("question"), choices: Array(choices.prefix(6)), from: guest) else {
                    return .init(content: [.text("The user didn't answer.")], isError: false)
                }
                return .init(content: [.text(answer)], isError: false)
            default:
                return .init(content: [.text("Unknown tool \(params.name).")], isError: true)
            }
        }
    }

    /// The first folder among the client's roots.
    static func folder(in roots: [Root]) -> URL? {
        roots.lazy.compactMap { URL(string: $0.uri) }.first { $0.isFileURL }
    }

    /// The work's result, or nil if it failed or took longer than `limit`. Doesn't wait for work that ignores
    /// cancellation, as a request to a client that never answers does.
    static func within<T: Sendable>(_ limit: Duration, _ work: @escaping @Sendable () async throws -> T) async -> T? {
        let first = Mutex<CheckedContinuation<T?, Never>?>(nil)
        let finish = { @Sendable (value: T?) in first.withLock { $0.take() }?.resume(returning: value) }
        return await withCheckedContinuation { continuation in
            first.withLock { $0 = continuation }
            Task { finish(try? await work()) }
            Task { try? await Task.sleep(for: limit); finish(nil) }
        }
    }

    private struct Method: Decodable { let method: String }

    private struct FixedID: SessionIDGenerator {
        let id: String
        func generateSessionID() -> String { id }
    }

    private static func response(from response: MCP.HTTPResponse) -> Response {
        var fields = HTTPFields()
        for (name, value) in response.headers {
            if let name = HTTPFields.Element.Name(name) { fields[name] = value }
        }
        let status = HTTPResponse.Status(code: response.statusCode)
        if case .stream(let events, _) = response {
            return Response(status: status, headers: fields, body: .init(asyncSequence: events.map { ByteBuffer(data: $0) }))
        }
        return Response(status: status, headers: fields, body: .init(byteBuffer: ByteBuffer(data: response.bodyData ?? Data())))
    }
}
