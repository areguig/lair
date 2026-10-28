import LairCore
import Testing

struct SpokenAnswerTests {
    @Test(arguments: ["Yes.", "Yeah, go ahead.", "Okay", "Sure, do it", "Allow it.", "Yes please."])
    func hearsYes(_ transcript: String) {
        #expect(SpokenAnswer.parse(transcript) == .allowOnce)
    }

    @Test(arguments: ["No.", "Nope", "Don't do that.", "Do not allow it", "Stop!", "No, don't do it.", "Cancel"])
    func hearsNo(_ transcript: String) {
        #expect(SpokenAnswer.parse(transcript) == .deny)
    }

    @Test(arguments: ["", "What does it do?", "Hmm, let me think", "Know what, maybe"])
    func asksAgainWhenUnclear(_ transcript: String) {
        #expect(SpokenAnswer.parse(transcript) == nil)
    }

    @Test(arguments: ["Always", "Always allow", "Yes, always", "Allow always", "Don't ask again", "Dont ask me again"])
    func hearsAlways(_ transcript: String) {
        #expect(SpokenAnswer.parse(transcript) == .allowAlways)
    }

    @Test func neverAllowingIsStillNo() {
        #expect(SpokenAnswer.parse("Never allow that") == .deny)
    }
}
