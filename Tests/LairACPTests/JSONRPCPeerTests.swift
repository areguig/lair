import Foundation
@testable import LairACP
import LairCore
import Testing

@Suite(.timeLimit(.minutes(1)))
struct JSONRPCPeerTests {
    private struct Params: Encodable { let value = 1 }
    private struct Echo: Decodable, Equatable { let echoed: Int }

    private func started(_ agent: FakeAgent, closed: @escaping @Sendable () -> Void = {}) -> JSONRPCPeer {
        let peer = JSONRPCPeer(channel: agent)
        peer.start(handle: { _ in }, closed: closed)
        return peer
    }

    @Test func matchesEachAnswerToItsRequest() async throws {
        let agent = FakeAgent()
        let peer = started(agent)
        let first = Task { try await peer.request("first", Params(), as: Echo.self) }
        let firstRequest = await agent.next()
        let second = Task { try await peer.request("second", Params(), as: Echo.self) }
        let secondRequest = await agent.next()
        // Answered in the other order.
        agent.answer(secondRequest, #"{"echoed":2}"#)
        agent.answer(firstRequest, #"{"echoed":1}"#)
        #expect(try await first.value == Echo(echoed: 1))
        #expect(try await second.value == Echo(echoed: 2))
    }

    @Test func anErrorAnswerThrowsIt() async throws {
        let agent = FakeAgent()
        let peer = started(agent)
        let result = Task { try await peer.request("nope", Params(), as: Echo.self) }
        let request = await agent.next()
        agent.say(#"{"jsonrpc":"2.0","id":\#(request.id!),"error":{"code":-32601,"message":"Method not found"}}"#)
        await #expect(throws: JSONRPCError(code: -32601, message: "Method not found")) { _ = try await result.value }
    }

    @Test func requestsWaitingWhenThePeerGoesAwayFailAsStopped() async throws {
        let agent = FakeAgent()
        let (closed, closing) = AsyncStream<Void>.makeStream()
        let peer = started(agent) { closing.finish() }
        let result = Task { try await peer.request("slow", Params(), as: Echo.self) }
        _ = await agent.next()
        agent.close()
        await #expect(throws: AgentStopped.self) { _ = try await result.value }
        for await _ in closed {}
        await #expect(throws: AgentStopped.self) { _ = try await peer.request("late", Params(), as: Echo.self) }
    }
}
