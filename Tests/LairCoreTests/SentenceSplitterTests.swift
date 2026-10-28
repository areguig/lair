import LairCore
import Testing

struct SentenceSplitterTests {
    @Test func cutsSentencesAcrossDeltas() {
        var splitter = SentenceSplitter()
        #expect(splitter.feed("Hello there") == [])
        #expect(splitter.feed("! Good to me") == ["Hello there!"])
        #expect(splitter.feed("et you.\nI'm ready") == ["Good to meet you."])
        #expect(splitter.flush() == "I'm ready")
    }

    @Test func keepsDecimalsAndWaitsForTrailingPunctuation() {
        var splitter = SentenceSplitter()
        #expect(splitter.feed("Version 3.5 is out.") == [])
        #expect(splitter.feed(" Next") == ["Version 3.5 is out."])
    }

    @Test func cutsOnNewlinesAndSkipsBlankLines() {
        var splitter = SentenceSplitter()
        #expect(splitter.feed("First line\n\nSecond line\n") == ["First line", "Second line"])
        #expect(splitter.flush() == nil)
    }
}
