import Foundation
import Hummingbird
import MCP

/// What an agent connected over MCP can do in the room. It's a guest: it talks to you, you don't start its turns.
public protocol GuestHost: Sendable {
    func speak(_ text: String, from guest: String) async
    /// Your answer, or nil if you didn't give one in time.
    func ask(_ question: String, from guest: String) async -> String?
}

/// Any agent on this Mac reaches you through `http://127.0.0.1:<port>/mcp/<its name>`.
/// One MCP session per connected agent, since an MCP server is initialized once per client.
public actor GuestServer {
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
                 Ask the user a question out loud, through Lair, and get their spoken answer as text. Use it \
                 when you need a decision to go on. One short question; offer the choices if there are any. \
                 If they don't answer in time you get no answer: carry on with what's safe or ask again later.
                 """,
             inputSchema: .object([
                 "type": "object",
                 "properties": .object(["question": .object(["type": "string", "description": "The question."])]),
                 "required": .array(["question"]),
             ])),
    ]

    private let host: any GuestHost
    private var sessions: [String: (server: Server, transport: StatefulHTTPServerTransport)] = [:]

    public init(host: any GuestHost) {
        self.host = host
    }

    /// Serves until cancelled; only this Mac can connect.
    public func run(port: Int) async throws {
        let router = Router()
        router.on("mcp/:guest", method: .post) { try await self.respond(to: $0, context: $1) }
        router.on("mcp/:guest", method: .get) { try await self.respond(to: $0, context: $1) }
        router.on("mcp/:guest", method: .delete) { try await self.respond(to: $0, context: $1) }
        let app = Application(router: router, configuration: .init(address: .hostname("127.0.0.1", port: port)))
        try await app.runService(gracefulShutdownSignals: [])
    }

    private func respond(to request: Request, context: BasicRequestContext) async throws -> Response {
        let guest = context.parameters.get("guest") ?? "Guest"
        let body = try await request.body.collect(upTo: 1 << 20)
        var headers: [String: String] = [:]
        for field in request.headers { headers[field.name.rawName] = field.value }
        let mcpRequest = MCP.HTTPRequest(method: request.method.rawValue, headers: headers,
                                     body: body.readableBytes > 0 ? Data(buffer: body) : nil, path: request.uri.path)
        return Self.response(from: await handle(mcpRequest, guest: guest))
    }

    func handle(_ request: MCP.HTTPRequest, guest: String) async -> MCP.HTTPResponse {
        if let id = request.header(HTTPHeaderName.sessionID), let session = sessions[id] {
            let response = await session.transport.handleRequest(request)
            if request.method == "DELETE", response.statusCode == 200 { sessions[id] = nil }
            return response
        }
        guard request.method == "POST", let body = request.body,
              (try? JSONDecoder().decode(Method.self, from: body))?.method == "initialize"
        else { return .error(statusCode: 404, .invalidRequest("Session not found; initialize first")) }
        let id = UUID().uuidString
        let transport = StatefulHTTPServerTransport(sessionIDGenerator: FixedID(id: id))
        let server = await makeServer(for: guest)
        do {
            try await server.start(transport: transport)
        } catch {
            return .error(statusCode: 500, .internalError(error.localizedDescription))
        }
        sessions[id] = (server, transport)
        return await transport.handleRequest(request)
    }

    private func makeServer(for guest: String) async -> Server {
        let server = Server(name: "lair", version: "0.1", capabilities: .init(tools: .init()))
        let host = host
        await server.withMethodHandler(ListTools.self) { _ in .init(tools: Self.tools) }
        await server.withMethodHandler(CallTool.self) { params in
            let argument = { (name: String) in params.arguments?[name]?.stringValue ?? "" }
            switch params.name {
            case "speak":
                guard !argument("text").isEmpty else { return .init(content: [.text("Nothing to say.")], isError: true) }
                await host.speak(argument("text"), from: guest)
                return .init(content: [.text("Said.")], isError: false)
            case "ask":
                guard !argument("question").isEmpty else { return .init(content: [.text("No question.")], isError: true) }
                guard let answer = await host.ask(argument("question"), from: guest) else {
                    return .init(content: [.text("The user didn't answer.")], isError: false)
                }
                return .init(content: [.text(answer)], isError: false)
            default:
                return .init(content: [.text("Unknown tool \(params.name).")], isError: true)
            }
        }
        return server
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
            let buffers = events.map { ByteBuffer(data: $0) }
            return Response(status: status, headers: fields, body: .init(asyncSequence: buffers))
        }
        return Response(status: status, headers: fields, body: .init(byteBuffer: ByteBuffer(data: response.bodyData ?? Data())))
    }
}
