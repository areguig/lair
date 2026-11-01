import Foundation
import LairCore

/// Newline-delimited messages to and from an agent.
public protocol LineChannel: Sendable {
    /// Everything the agent sends, one message per element; ends when the agent goes away.
    var lines: AsyncThrowingStream<Data, Error> { get }
    func send(_ line: Data) throws
    func close()
}

/// An agent run as a child process, talking on stdin and stdout; what it prints on stderr goes to its log.
public final class ProcessChannel: LineChannel {
    private let process = Process()
    private let input = Pipe()
    public let lines: AsyncThrowingStream<Data, Error>

    public init(command: [String], directory: URL?, environment: [String: String]?, errorLog: URL?) throws {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command
        process.currentDirectoryURL = directory
        if let environment { process.environment = environment }
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = AgentLog.handle(for: errorLog)
        try AgentLog.run(process)
        let reading = output.fileHandleForReading
        lines = AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await line in reading.bytes.lines {
                        AgentLog.stray(line)
                        continuation.yield(Data(line.utf8))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func send(_ line: Data) throws {
        guard process.isRunning else { throw AgentStopped() }
        try input.fileHandleForWriting.write(contentsOf: line + Data("\n".utf8))
    }

    public func close() {
        process.terminate()
    }
}
