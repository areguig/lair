import Testing

@testable import LairCore

struct ShowFilterTests {
    private func run(_ chunks: [String]) -> ShowFilter.Output {
        var f = ShowFilter()
        var all = ShowFilter.Output(spoken: "", shown: [])
        for c in chunks + [""] {
            let o = c.isEmpty ? f.flush() : f.feed(c)
            all.spoken += o.spoken
            all.shown += o.shown
        }
        return all
    }

    @Test func wholeTag() {
        let o = run(["I updated <show>~/.config/lair/config.json</show> and pushed."])
        #expect(o.spoken == "I updated and pushed.")
        #expect(o.shown == ["~/.config/lair/config.json"])
    }

    @Test func wordsAroundATagWithoutSpacesStayApart() {
        let o = run(["Open the file<show>~/a.txt</show>and check it, or <show>b</show>, then go."])
        #expect(o.spoken == "Open the file and check it, or , then go.")
    }

    @Test func everySplitMatchesOneShot() {
        let samples = [
            "I updated <show>~/.config/x</show> and <SHOW> y </Show>pushed a < b <sh no.",
            "config<show>x</show>and <show>a<b</sh</show> end",
        ]
        for s in samples {
            let expected = run([s])
            let chars = Array(s)
            for cut in 0...chars.count {
                let got = run([String(chars[..<cut]), String(chars[cut...])])
                #expect(got == expected, "cut \(cut) of \(s)")
            }
            #expect(run(chars.map { String($0) }) == expected)
        }
    }

    @Test func multipleTags() {
        let o = run(["a <show>one</show> b <show>two</show> c"])
        #expect(o.spoken == "a b c")
        #expect(o.shown == ["one", "two"])
    }

    @Test func uppercase() {
        let o = run(["x <SHOW>Y</SHOW> z"])
        #expect(o.spoken == "x z")
        #expect(o.shown == ["Y"])
    }

    @Test func loneLessThanSpoken() {
        #expect(run(["a < b"]).spoken == "a < b")
    }

    @Test func unclosedGoesToShown() {
        let o = run(["see <show>oops"])
        #expect(o.spoken == "see ")
        #expect(o.shown == ["oops"])
    }

    @Test func heldBackAtFlushIsSpoken() {
        var f = ShowFilter()
        let a = f.feed("hi <sh")
        #expect(a.spoken == "hi ")
        #expect(f.flush().spoken == "<sh")
    }

    @Test func emptyDropped() {
        let o = run(["a<show></show>b <show>  </show>c"])
        #expect(o.shown.isEmpty)
        #expect(o.spoken == "a b c")
    }

    @Test func passthrough() {
        let o = run(["hello ", "world."])
        #expect(o.spoken == "hello world.")
        #expect(o.shown.isEmpty)
    }
}
