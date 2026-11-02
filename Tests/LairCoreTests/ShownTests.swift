import Foundation
import Testing

@testable import LairCore

struct ShownTests {
    private func label(_ item: String, home: String = "/Users/me") -> String { Shown(item: item, at: 0).label(home: home) }

    @Test func markdownLinkIsItsTitle() {
        #expect(label("[Predictwind's Paris weather](https://www.predictwind.com/weather/france/paris)") == "Predictwind's Paris weather")
        #expect(Shown(item: "[x](https://a.io/b)", at: 0).target == .link(URL(string: "https://a.io/b")!))
    }

    @Test func bareURLIsItsSite() {
        #expect(label("https://www.predictwind.com/weather/france/paris") == "predictwind.com")
        #expect(label("http://localhost:3000/app") == "localhost")
    }

    @Test func pathsAreAbbreviated() {
        #expect(label("/Users/me/notes.md") == "~/notes.md")
        #expect(label("/Users/me") == "~")
        #expect(label("~/dev/app") == "~/dev/app")
        #expect(label("/Users/me/dev/app/CHANGELOG.md") == "…/app/CHANGELOG.md")
        #expect(label("/etc/hosts") == "/etc/hosts")
        #expect(label("/var/log/system/today.log") == "…/system/today.log")
        #expect(Shown(item: "~/a.txt", at: 0).target == .path("~/a.txt"))
    }

    @Test func anythingElseIsACommandAsIs() {
        #expect(label("swift test --filter Shown") == "swift test --filter Shown")
        #expect(Shown(item: "swift test", at: 0).target == .command)
        #expect(Shown(item: "[x](ftp://a.io)", at: 0).target == .command)
    }

    @Test func itemsKeepTheirPlaceInTheSentence() {
        var stream = SpokenStream()
        var text = ""
        var placed: [Shown] = []
        for delta in ["The source is <show>[P](https://a.io)</show>.", " Done."] {
            let piece = stream.feed(delta, after: text)
            placed += Shown.place(piece, after: text)
            text += piece.text
        }
        #expect(text == "The source is . Done.")
        #expect(placed == [Shown(item: "[P](https://a.io)", at: 14)])
    }

    @Test func aTagSplitAcrossDeltasStillLandsInPlace() {
        var stream = SpokenStream()
        var text = ""
        var placed: [Shown] = []
        for delta in ["See <sh", "ow>~/a.txt</sh", "ow> and <show>ls</show> now."] {
            let piece = stream.feed(delta, after: text)
            placed += Shown.place(piece, after: text)
            text += piece.text
        }
        #expect(text == "See and now.")
        #expect(placed.map(\.item) == ["~/a.txt", "ls"])
        #expect(placed.map(\.at) == [4, 8])
    }

    @Test func aGluedMessageShiftsTheItemByItsSpace() {
        var stream = SpokenStream()
        _ = stream.feed("Good night.", after: "")
        let piece = stream.feed("Open <show>x</show>.", after: "Good night.")
        #expect(piece.text == " Open .")
        #expect(piece.placed == [Shown(item: "x", at: 6)])
    }

    @Test func aForgottenCloseTagStillShowsTheItem() {
        var stream = SpokenStream()
        _ = stream.feed("See <show>~/a", after: "")
        let end = stream.finish()
        #expect(end.placed == [Shown(item: "~/a", at: 0)])
    }

    @Test func segmentsInterleaveTextAndItems() {
        let shown = [Shown(item: "a", at: 5), Shown(item: "b", at: 8)]
        #expect(Shown.segments(of: "Open or then go.", shown) == [
            .text("Open "), .item(shown[0]), .text(" or "), .item(shown[1]), .text(" then go.")])
        #expect(Shown.segments(of: "Hi", []) == [.text("Hi")])
        #expect(Shown.segments(of: "", [Shown(item: "x", at: 0)]) == [.item(Shown(item: "x", at: 0))])
        #expect(Shown.segments(of: "Hi", [Shown(item: "x", at: 9)]) == [.text("Hi "), .item(Shown(item: "x", at: 9))])
    }

    @Test func aWordTouchingAnItemGetsItsSpaceBack() {
        let item = Shown(item: "x", at: 10)
        #expect(Shown.segments(of: "I updated and bumped it", [item]) == [.text("I updated "), .item(item), .text(" and bumped it")])
        #expect(Shown.segments(of: "I updated and bumped it", [Shown(item: "x", at: 9)]) == [
            .text("I updated "), .item(Shown(item: "x", at: 9)), .text(" and bumped it")])
    }
}
