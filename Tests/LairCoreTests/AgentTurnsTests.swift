@testable import LairCore
import Testing

struct AgentTurnsTests {
    private func collect(_ reply: AsyncThrowingStream<AgentReply, Error>) async throws -> [AgentReply] {
        var replies: [AgentReply] = []
        for try await reply in reply { replies.append(reply) }
        return replies
    }

    @Test func routesATurnUntilItsResult() async throws {
        let turns = AgentTurns()
        let reply = turns.begin()
        turns.receive(.textDelta("Hi"))
        turns.receive(.finished("Hi"))
        turns.receive(.textDelta("late"))
        #expect(try await collect(reply) == [.text("Hi")])
    }

    @Test func dropsTheOldTurnAfterAnInterrupt() async throws {
        let turns = AgentTurns()
        let first = turns.begin()
        turns.receive(.textDelta("1 2 3"))
        #expect(turns.interrupt())
        turns.receive(.textDelta("4 5 6"))
        let second = turns.begin()
        turns.receive(.textDelta("7 8"))
        turns.receive(.finished(""))
        turns.receive(.textDelta("ok"))
        turns.receive(.finished("ok"))
        #expect(try await collect(first) == [.text("1 2 3")])
        #expect(try await collect(second) == [.text("ok")])
    }

    @Test func doesNotDrainWhenNothingIsRunning() async throws {
        let turns = AgentTurns()
        let first = turns.begin()
        turns.receive(.finished(""))
        #expect(turns.interrupt() == false)
        let second = turns.begin()
        turns.receive(.textDelta("next"))
        turns.receive(.finished(""))
        #expect(try await collect(first).isEmpty)
        #expect(try await collect(second) == [.text("next")])
    }

    @Test func closingEndsTheTurn() async throws {
        let turns = AgentTurns()
        let reply = turns.begin()
        turns.close()
        #expect(try await collect(reply).isEmpty)
    }

    @Test func aFailedTurnThrowsItsMessage() async {
        let turns = AgentTurns()
        let reply = turns.begin()
        turns.receive(.failed("No API key"))
        await #expect(throws: AgentFailure.self) { _ = try await collect(reply) }
    }

    @Test func aFailureAlsoEndsDraining() async throws {
        let turns = AgentTurns()
        _ = turns.begin()
        turns.receive(.textDelta("x"))
        #expect(turns.interrupt())
        turns.receive(.failed("aborted"))
        let next = turns.begin()
        turns.receive(.textDelta("fresh"))
        turns.receive(.finished(""))
        #expect(try await collect(next) == [.text("fresh")])
    }
}
