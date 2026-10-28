import LairCore
import Testing

struct SpokenAnswerTests {
    @Test(arguments: ["Yes.", "Yeah, go ahead.", "Okay", "Sure, do it", "Allow it.", "Yes please."])
    func hearsYes(_ transcript: String) {
        #expect(SpokenAnswer.parse(transcript) == true)
    }

    @Test(arguments: ["No.", "Nope", "Don't do that.", "Do not allow it", "Stop!", "No, don't do it.", "Cancel"])
    func hearsNo(_ transcript: String) {
        #expect(SpokenAnswer.parse(transcript) == false)
    }

    @Test(arguments: ["", "What does it do?", "Hmm, let me think", "Know what, maybe"])
    func asksAgainWhenUnclear(_ transcript: String) {
        #expect(SpokenAnswer.parse(transcript) == nil)
    }
}
