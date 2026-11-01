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

    /// Its input pipe fills up and stays full: sending must still return at once.
    @Test func sendingToAnAgentThatDoesNotReadDoesNotWait() throws {
        let channel = try ProcessChannel(command: ["sleep", "30"], directory: nil, environment: nil, errorLog: nil)
        defer { channel.close() }
        let line = Data(repeating: UInt8(ascii: "x"), count: 1024)
        let start = ContinuousClock.now
        for _ in 0..<300 { try channel.send(line) }
        #expect(ContinuousClock.now - start < .seconds(1))
    }

    /// Several agents at once, most of them quiet: the quiet ones never hold up the one that talks.
    @Test func quietAgentsDoNotHoldUpTheOthers() async throws {
        let quiet = try (0..<16).map { _ in try ProcessChannel(command: ["cat"], directory: nil, environment: nil, errorLog: nil) }
        defer { quiet.forEach { $0.close() } }
        for channel in quiet { Task { for try await _ in channel.lines {} } }
        try await withThrowingTaskGroup(of: String?.self) { group in
            for index in 0..<4 {
                group.addTask {
                    let talking = try ProcessChannel(command: ["cat"], directory: nil, environment: nil, errorLog: nil)
                    defer { talking.close() }
                    var lines = talking.lines.makeAsyncIterator()
                    try talking.send(Data("hello \(index)".utf8))
                    return try await lines.next().map { String(decoding: $0, as: UTF8.self) }
                }
            }
            var answers: [String] = []
            for try await answer in group { answers.append(answer ?? "") }
            #expect(answers.sorted() == (0..<4).map { "hello \($0)" })
        }
    }

    @Test func echoesWhatItIsSent() async throws {
        let channel = try ProcessChannel(command: ["cat"], directory: nil, environment: nil, errorLog: nil)
        var lines = channel.lines.makeAsyncIterator()
        try channel.send(Data(#"{"ping":1}"#.utf8))
        #expect(try await lines.next().map { String(decoding: $0, as: UTF8.self) } == #"{"ping":1}"#)
        channel.close()
    }
}
