@testable import LairCore
import Testing

struct AgentTurnsTests {
    private func collect(_ reply: AgentTurn) async throws -> [AgentReply] {
        var replies: [AgentReply] = []
        for try await reply in reply { replies.append(reply) }
        return replies
    }

    @Test func routesYourTurnFromYourMessageUntilItsResult() async throws {
        let turns = AgentTurns()
        let reply = turns.begin()
        turns.receive(.yourMessage)
        turns.receive(.textDelta("Hi"))
        turns.receive(.finished("Hi"))
        turns.close()
        #expect(try await collect(reply) == [.text("Hi")])
    }

    @Test func whatTheAgentSaysUnaskedIsATurnOfItsOwn() async throws {
        let turns = AgentTurns()
        var own = turns.ownTurns.makeAsyncIterator()
        turns.receive(.textDelta("The build passed."))
        turns.receive(.finished(""))
        let turn = try #require(await own.next())
        #expect(try await collect(turn) == [.text("The build passed.")])
    }

    @Test func yourMessageTakenInMidwayEndsTheAgentsOwnTurn() async throws {
        let turns = AgentTurns()
        var own = turns.ownTurns.makeAsyncIterator()
        turns.receive(.textDelta("Background job done."))
        let reply = turns.begin()
        turns.receive(.textDelta(" More on it."))
        turns.receive(.yourMessage)
        turns.receive(.textDelta("Yes."))
        turns.receive(.idle)
        turns.receive(.finished(""))
        let turn = try #require(await own.next())
        #expect(try await collect(turn) == [.text("Background job done."), .text(" More on it.")])
        #expect(try await collect(reply) == [.text("Yes.")])
    }

    @Test func idleEndsOnlyTheAgentsOwnTurn() async throws {
        let turns = AgentTurns()
        var own = turns.ownTurns.makeAsyncIterator()
        turns.receive(.textDelta("Done."))
        turns.receive(.idle)
        let reply = turns.begin()
        turns.receive(.yourMessage)
        turns.receive(.textDelta("Sure"))
        turns.receive(.idle)
        turns.receive(.textDelta("."))
        turns.receive(.finished(""))
        #expect(try await collect(try #require(await own.next())) == [.text("Done.")])
        #expect(try await collect(reply) == [.text("Sure"), .text(".")])
    }

    @Test func dropsTheOldTurnAfterAnInterrupt() async throws {
        let turns = AgentTurns()
        let first = turns.begin()
        turns.receive(.yourMessage)
        turns.receive(.textDelta("1 2 3"))
        #expect(turns.interrupt())
        turns.receive(.textDelta("4 5 6"))
        turns.receive(.finished(""))
        let second = turns.begin()
        turns.receive(.yourMessage)
        turns.receive(.textDelta("ok"))
        turns.receive(.finished("ok"))
        #expect(try await collect(first) == [.text("1 2 3")])
        #expect(try await collect(second) == [.text("ok")])
    }

    @Test func anInterruptBeforeTheAgentTookYourMessageInDropsItsTurn() async throws {
        let turns = AgentTurns()
        let first = turns.begin()
        #expect(turns.interrupt())
        turns.receive(.yourMessage)
        turns.receive(.textDelta("too late"))
        turns.receive(.finished(""))
        let second = turns.begin()
        turns.receive(.yourMessage)
        turns.receive(.textDelta("next"))
        turns.receive(.finished(""))
        #expect(try await collect(first).isEmpty)
        #expect(try await collect(second) == [.text("next")])
    }

    @Test func doesNotDrainWhenNothingIsOpen() async throws {
        let turns = AgentTurns()
        let first = turns.begin()
        turns.receive(.yourMessage)
        turns.receive(.finished(""))
        #expect(turns.interrupt() == false)
        let second = turns.begin()
        turns.receive(.yourMessage)
        turns.receive(.textDelta("next"))
        turns.receive(.finished(""))
        #expect(try await collect(first).isEmpty)
        #expect(try await collect(second) == [.text("next")])
    }

    @Test func closingFailsEveryOpenTurnAsStopped() async {
        let turns = AgentTurns()
        let reply = turns.begin()
        turns.close()
        await #expect(throws: AgentStopped.self) { _ = try await collect(reply) }
    }

    @Test func aFailedTurnThrowsItsMessage() async {
        let turns = AgentTurns()
        let reply = turns.begin()
        turns.receive(.yourMessage)
        turns.receive(.failed("No API key"))
        await #expect(throws: AgentFailure.self) { _ = try await collect(reply) }
    }

    @Test func aMessageRefusedBeforeItWasTakenInFailsItsTurn() async {
        let turns = AgentTurns()
        let reply = turns.begin()
        turns.receive(.failed("No API key"))
        await #expect(throws: AgentFailure.self) { _ = try await collect(reply) }
    }

    @Test func aFailureAlsoEndsDraining() async throws {
        let turns = AgentTurns()
        _ = turns.begin()
        turns.receive(.yourMessage)
        turns.receive(.textDelta("x"))
        #expect(turns.interrupt())
        turns.receive(.failed("aborted"))
        let next = turns.begin()
        turns.receive(.yourMessage)
        turns.receive(.textDelta("fresh"))
        turns.receive(.finished(""))
        #expect(try await collect(next) == [.text("fresh")])
    }
}
