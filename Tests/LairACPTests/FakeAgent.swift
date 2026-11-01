import Foundation
@testable import LairACP
import LairCore

/// The agent's end of a session, scripted by a test: it reads what Lair sends and answers with raw JSON.
final class FakeAgent: LineChannel, @unchecked Sendable {
    let lines: AsyncThrowingStream<Data, Error>
    private let says: AsyncThrowingStream<Data, Error>.Continuation
    private var received: AsyncStream<Data>.Iterator
    private let receivedContinuation: AsyncStream<Data>.Continuation

    /// A message from Lair.
    struct Message {
        let object: [String: Any]
        var method: String? { object["method"] as? String }
        var id: Any? { object["id"] }
        var params: [String: Any] { object["params"] as? [String: Any] ?? [:] }
        var result: [String: Any] { object["result"] as? [String: Any] ?? [:] }
    }

    init() {
        (lines, says) = AsyncThrowingStream<Data, Error>.makeStream()
        let (stream, continuation) = AsyncStream<Data>.makeStream()
        received = stream.makeAsyncIterator()
        receivedContinuation = continuation
    }

    func send(_ line: Data) throws { receivedContinuation.yield(line) }
    func close() { says.finish() }

    func say(_ json: String) { says.yield(Data(json.utf8)) }

    func next() async -> Message {
        let data = await received.next()!
        return Message(object: try! JSONSerialization.jsonObject(with: data) as! [String: Any])
    }

    func answer(_ message: Message, _ resultJSON: String) {
        let id = message.id.map { "\($0)" } ?? "null"
        say(#"{"jsonrpc":"2.0","id":\#(id),"result":\#(resultJSON)}"#)
    }

    func update(_ updateJSON: String) {
        say(#"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"s1","update":\#(updateJSON)}}"#)
    }

    static let options = """
        [{"id":"model","name":"Model","category":"model","type":"select","currentValue":"sonnet",
          "options":[{"value":"sonnet","name":"Sonnet"},{"value":"opus","name":"Claude Opus"}]},
         {"id":"effort","name":"Effort","category":"thought_level","type":"select","currentValue":"low",
          "options":[{"group":"g","name":"Levels","options":[{"value":"low","name":"low"},{"value":"high","name":"high"}]}]},
         {"id":"fast","name":"Fast","type":"boolean","currentValue":true}]
        """

    /// Answers `initialize` and `session/new`, and returns what Lair asked for.
    @discardableResult
    func handshake() async -> (initialize: Message, newSession: Message) {
        let initialize = await next()
        answer(initialize, #"{"protocolVersion":1,"agentInfo":{"name":"fake","version":"0"}}"#)
        let newSession = await next()
        answer(newSession, #"{"sessionId":"s1","configOptions":\#(Self.options)}"#)
        return (initialize, newSession)
    }
}

func collect(_ turn: AgentTurn) async throws -> [AgentReply] {
    var replies: [AgentReply] = []
    for try await reply in turn { replies.append(reply) }
    return replies
}
