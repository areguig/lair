import Foundation
import LairCore
import Synchronization

/// Newline-delimited messages to and from an agent.
public protocol LineChannel: Sendable {
    /// Everything the agent sends, one message per element; ends when the agent goes away.
    var lines: AsyncThrowingStream<Data, Error> { get }
    func send(_ line: Data) throws
    func close()
}

/// An agent run as a child process, talking on stdin and stdout; what it prints on stderr goes to its log.
///
/// Its output is read by `readabilityHandler`, on a system thread: `FileHandle.bytes` blocks one of Swift's task
/// threads in `read()` while the agent is quiet, and in an app with one such thread that froze every call.
public final class ProcessChannel: LineChannel {
    private let process = Process()
    private let input = Pipe()
    /// Writes in order on a system thread: an agent that stops reading must not stall whoever is sending.
    private let writer = DispatchQueue(label: "lair.agent.input")
    public let lines: AsyncThrowingStream<Data, Error>

    public init(command: [String], directory: URL?, environment: [String: String]?, errorLog: URL?) throws {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command
        process.currentDirectoryURL = directory
        if let environment { process.environment = environment }
        let output = Pipe()
        process.standardInput = input
        // Writing after the agent went away fails with an error instead of a SIGPIPE that ends the app.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        process.standardOutput = output
        process.standardError = AgentLog.handle(for: errorLog)
        let (lines, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
        self.lines = lines
        let splitter = Mutex(LineSplitter())
        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            let complete = splitter.withLock { chunk.isEmpty ? $0.finish() : $0.feed(chunk) }
            for line in complete {
                AgentLog.stray(String(decoding: line, as: UTF8.self))
                continuation.yield(line)
            }
            guard chunk.isEmpty else { return }
            handle.readabilityHandler = nil
            continuation.finish()
        }
        try AgentLog.run(process)
    }

    /// Queues the line; one that can't be written because the agent went away is dropped, and its end of `lines`
    /// tells the rest.
    public func send(_ line: Data) throws {
        guard process.isRunning else { throw AgentStopped() }
        let input = input.fileHandleForWriting
        writer.async { try? input.write(contentsOf: line + Data("\n".utf8)) }
    }

    public func close() {
        process.terminate()
    }
}

/// Cuts a byte stream into lines, keeping a partial line until the rest arrives.
struct LineSplitter {
    private var pending = Data()

    /// The lines `chunk` completes, without their line ends (`\n` or `\r\n`); empty lines are skipped.
    mutating func feed(_ chunk: Data) -> [Data] {
        pending.append(chunk)
        var lines: [Data] = []
        while let end = pending.firstIndex(of: UInt8(ascii: "\n")) {
            var line = pending[pending.startIndex..<end]
            if line.last == UInt8(ascii: "\r") { line = line.dropLast() }
            if !line.isEmpty { lines.append(Data(line)) }
            pending = Data(pending[pending.index(after: end)...])
        }
        return lines
    }

    /// The last line, when the stream ends without a line end.
    mutating func finish() -> [Data] {
        defer { pending = Data() }
        return pending.isEmpty ? [] : [pending]
    }
}
