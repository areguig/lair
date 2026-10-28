import LairCore
import Testing

struct SpeakableTests {
    @Test func dropsMarkdownSymbols() {
        #expect(Speakable.text("**Bold** and `code` and _soft_.") == "Bold and code and soft.")
    }

    @Test func keepsLinkLabelsOnly() {
        #expect(Speakable.text("See [the docs](https://example.com).") == "See the docs.")
    }

    @Test func dropsBulletsAndHeadings() {
        #expect(Speakable.text("## Steps") == "Steps")
        #expect(Speakable.text("- first item") == "first item")
        #expect(Speakable.text("2. second item") == "second item")
    }

    @Test func leavesPlainSentencesAlone() {
        #expect(Speakable.text("It costs 3.5 euros, I think.") == "It costs 3.5 euros, I think.")
    }
}
