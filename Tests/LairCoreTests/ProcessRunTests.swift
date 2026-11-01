import Foundation
import LairCore
import Testing

@Suite(.timeLimit(.minutes(1)))
struct ProcessRunTests {
    private func command(_ arguments: [String]) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        return process
    }

    /// More than a pipe holds: read only after the end, the command would wait forever for a reader.
    @Test func finishesACommandThatPrintsMoreThanAPipeHolds() async throws {
        let result = try await ProcessRun.run(command(["head", "-c", "300000", "/dev/zero"]))
        #expect(result.status == 0)
        #expect(result.output.utf8.count == 300_000)
    }

    @Test func givesTheStatusAndTheErrorsWhenAsked() async throws {
        let result = try await ProcessRun.run(command(["sh", "-c", "echo oops >&2; exit 3"]), includingErrors: true)
        #expect(result.status == 3)
        #expect(result.output == "oops\n")
        #expect(try await ProcessRun.run(command(["sh", "-c", "echo oops >&2"])).output.isEmpty)
    }

    /// Each one waits on a system thread: twenty at once take about as long as one.
    @Test func manyRunAtOnceWithoutWaitingForEachOther() async throws {
        let start = ContinuousClock.now
        try await withThrowingTaskGroup(of: Int32.self) { group in
            for _ in 0..<20 { group.addTask { try await ProcessRun.run(self.command(["sleep", "0.5"])).status } }
            for try await status in group { #expect(status == 0) }
        }
        #expect(ContinuousClock.now - start < .seconds(5))
    }
}
