import Foundation
@testable import LairACP
import Testing

struct LineSplitterTests {
    private func text(_ lines: [Data]) -> [String] { lines.map { String(decoding: $0, as: UTF8.self) } }

    @Test func keepsAPartialLineUntilItsEndArrives() {
        var splitter = LineSplitter()
        #expect(text(splitter.feed(Data("{\"a\":1}\n{\"b\"".utf8))) == [#"{"a":1}"#])
        #expect(text(splitter.feed(Data(":2}\r\n\n".utf8))) == [#"{"b":2}"#])
        #expect(splitter.finish().isEmpty)
    }

    @Test func givesTheLastLineWhenTheStreamEndsWithoutALineEnd() {
        var splitter = LineSplitter()
        #expect(splitter.feed(Data("tail".utf8)).isEmpty)
        #expect(text(splitter.finish()) == ["tail"])
    }
}

@Suite(.timeLimit(.minutes(1)))
struct ProcessChannelTests {
    @Test func readsAnAgentsLinesUntilItExits() async throws {
        let channel = try ProcessChannel(command: ["printf", "one\\ntwo\\nthree"], directory: nil, environment: nil, errorLog: nil)
        var lines: [String] = []
        for try await line in channel.lines { lines.append(String(decoding: line, as: UTF8.self)) }
        #expect(lines == ["one", "two", "three"])
    }

    @Test func echoesWhatItIsSent() async throws {
        let channel = try ProcessChannel(command: ["cat"], directory: nil, environment: nil, errorLog: nil)
        var lines = channel.lines.makeAsyncIterator()
        try channel.send(Data(#"{"ping":1}"#.utf8))
        #expect(try await lines.next().map { String(decoding: $0, as: UTF8.self) } == #"{"ping":1}"#)
        channel.close()
    }
}
