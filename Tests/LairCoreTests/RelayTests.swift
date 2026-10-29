import LairCore
import Testing

struct RelayTests {
    private let names = ["Claude", "Echo", "Nova"]

    @Test func passesOnFromTheNamedAgent() {
        let relay = Relay.parse("Nova, ask Claude what he thinks about this.", names: names)
        #expect(relay == Relay(source: "Nova", target: "Claude", words: "Nova, ask Claude what he thinks about this."))
    }

    @Test func passesOnFromTheAgentInFocusWhenNoneIsNamed() {
        #expect(Relay.parse("Ask Echo to do it", names: names)?.source == nil)
        #expect(Relay.parse("hey Claude, tell Echo to check the backups", names: names)?.target == "Echo")
        #expect(Relay.parse("Can you ask Echo whether the backups ran?", names: names)?.target == "Echo")
        #expect(Relay.parse("Claude, have Nova run the tests", names: names)?.target == "Nova")
    }

    @Test func needsAnotherAgentAndSomethingToPassOn() {
        #expect(Relay.parse("Claude, ask Claude to do it", names: names) == nil)
        #expect(Relay.parse("Ask Echo.", names: names) == nil)
        #expect(Relay.parse("Ask the team what they think", names: names) == nil)
        #expect(Relay.parse("Echoes, ask Nova", names: names) == nil)
        #expect(Relay.parse("What did Echo say?", names: names) == nil)
    }

    @Test func aRelayIsNotAnAddressedSentence() {
        #expect(Relay.parse("Echo, check the backups", names: names) == nil)
    }
}

struct FollowUpTests {
    @Test(arguments: ["Want me to do both?", "Should I push it?\"", "Which one? ", "Okay (or not?)"])
    func hearsAQuestion(_ words: String) {
        #expect(FollowUp.expectsAnswer(words))
    }

    @Test(arguments: ["Done.", "I asked why? Because it failed.", ""])
    func hearsNoQuestion(_ words: String) {
        #expect(!FollowUp.expectsAnswer(words))
    }

    @Test func sendsOnceYouStopTalking() {
        var turn = FollowUp.Turn()
        #expect(turn.update(speaking: false, elapsed: .seconds(1)) == .listen)
        #expect(turn.update(speaking: true, elapsed: .seconds(2)) == .listen)
        #expect(turn.update(speaking: true, elapsed: .seconds(3)) == .listen)
        #expect(turn.update(speaking: false, elapsed: .seconds(4)) == .send)
    }

    @Test func givesUpWhenYouSayNothing() {
        var turn = FollowUp.Turn()
        #expect(turn.update(speaking: false, elapsed: .seconds(7)) == .listen)
        #expect(turn.update(speaking: false, elapsed: .seconds(8)) == .giveUp)
    }

    @Test func aShortNoiseIsNotAnAnswer() {
        var turn = FollowUp.Turn()
        #expect(turn.update(speaking: true, elapsed: .milliseconds(1_000)) == .listen)
        #expect(turn.update(speaking: false, elapsed: .milliseconds(1_200)) == .listen)
        #expect(turn.update(speaking: false, elapsed: .seconds(8)) == .giveUp)
    }

    @Test func waitsForYouWhileYouTalkPastThePatience() {
        var turn = FollowUp.Turn()
        #expect(turn.update(speaking: true, elapsed: .milliseconds(7_800)) == .listen)
        #expect(turn.update(speaking: true, elapsed: .seconds(9)) == .listen)
        #expect(turn.update(speaking: true, elapsed: .seconds(30)) == .send)
    }
}

struct VoicePromptRelayTests {
    @Test func carriesTheWordsAndTheLatestExchange() {
        let prompt = VoicePrompt.relay("Nova, ask Claude what he thinks", from: "Nova",
                                       asked: "Should we cache it?", answered: "I'd cache it for an hour.")
        #expect(prompt.contains("\"Nova, ask Claude what he thinks\""))
        #expect(prompt.contains("The user: \"Should we cache it?\""))
        #expect(prompt.contains("Nova: \"I'd cache it for an hour.\""))
    }

    @Test func leavesOutContextThereIsNone() {
        #expect(!VoicePrompt.relay("ask Echo", from: "Claude", asked: nil, answered: nil).contains("context"))
    }
}
