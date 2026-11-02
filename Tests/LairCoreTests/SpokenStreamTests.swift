import Testing

@testable import LairCore

struct SpokenStreamTests {
    @Test func sentencesComeOutOnceComplete() {
        var stream = SpokenStream()
        let first = stream.feed("Hello the", after: "")
        #expect(first.text == "Hello the")
        #expect(first.sentences.isEmpty)
        let second = stream.feed("re. How are", after: "Hello the")
        #expect(second.sentences == ["Hello there."])
        #expect(second.text == "re. How are")
    }

    @Test func showTagSplitAcrossDeltasGoesToShownOnly() {
        var stream = SpokenStream()
        var pieces = [stream.feed("Open <sh", after: "")]
        pieces.append(stream.feed("ow>~/a.txt</sh", after: "Open "))
        pieces.append(stream.feed("ow> now. Then", after: "Open "))
        #expect(pieces.flatMap(\.shown) == ["~/a.txt"])
        #expect(pieces.map(\.text).joined() == "Open now. Then")
        #expect(pieces.flatMap(\.sentences) == ["Open now."])
    }

    @Test func messagesSentGluedGetASpaceBetween() {
        var stream = SpokenStream()
        _ = stream.feed("Good night.", after: "")
        let next = stream.feed("Nothing more.", after: "Good night.")
        #expect(next.text == " Nothing more.")
        #expect(next.sentences == ["Good night."])
        #expect(stream.finish().sentences == ["Nothing more."])
    }

    @Test func finishGivesTheTrailingPartSentence() {
        var stream = SpokenStream()
        _ = stream.feed("One. Two and", after: "")
        let end = stream.finish()
        #expect(end.sentences == ["Two and"])
        #expect(end.text.isEmpty)
    }

    @Test func finishSpeaksWhatTheFilterHeldBack() {
        var stream = SpokenStream()
        _ = stream.feed("a < b", after: "")
        let end = stream.finish()
        #expect(end.text == "")
        #expect(end.sentences == ["a < b"])
    }

    @Test func finishAtAnApprovalThenMoreText() {
        var stream = SpokenStream()
        _ = stream.feed("Let me run it", after: "")
        #expect(stream.finish().sentences == ["Let me run it"])
        let after = stream.feed("Done. Next", after: "")
        #expect(after.sentences == ["Done."])
        #expect(stream.finish().sentences == ["Next"])
    }
}
