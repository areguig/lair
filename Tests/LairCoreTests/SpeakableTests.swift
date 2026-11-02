import LairCore
import Testing

struct SpeakableTests {
    @Test func linesWithNothingToSayAreSilent() {
        #expect(Speakable.text("---") == "")
        #expect(Speakable.text("…") == "")
        #expect(Speakable.text("* * *") == "")
        #expect(Speakable.text("Step 2.") == "Step 2.")
    }

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

    @Test func shortLowercaseNamesAreSpelledOut() {
        #expect(Speakable.name("omp") == "O M P")
        #expect(Speakable.name("Claude Code") == "Claude Code")
        #expect(Speakable.name("Nova") == "Nova")
        #expect(Speakable.name("zed2") == "zed2")
        // French names, accented or not, are handled the same way.
        #expect(Speakable.name("léa") == "L É A")
        #expect(Speakable.name("Édith") == "Édith")
    }

    @Test func gluedSentencesGetASpace() {
        #expect(Speakable.gap(after: "Have a good night.", before: "Nothing new.") == " ")
        #expect(Speakable.gap(after: "It costs 3.", before: "5 euros") == "")
        #expect(Speakable.gap(after: "Hello ", before: "World") == "")
        #expect(Speakable.gap(after: "", before: "Hi") == "")
    }
}
