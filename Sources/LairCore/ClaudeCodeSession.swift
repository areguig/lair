import Foundation
import Synchronization

/// One long-lived `claude -p` process per call, so only the first turn pays for its startup.
public final class ClaudeCodeSession: Sendable {
    private let process = Process()
    private let input = Pipe()
    private let currentTurn = Mutex<AsyncStream<String>.Continuation?>(nil)

    public init(model: String? = nil, systemPrompt: String = VoicePrompt.text) throws {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["claude", "-p", "--input-format", "stream-json", "--output-format", "stream-json",
                             "--verbose", "--include-partial-messages", "--no-session-persistence",
                             "--append-system-prompt", systemPrompt]
            + (model.map { ["--model", $0] } ?? [])
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        Task { await routeReplies(from: output.fileHandleForReading) }
    }

    private func routeReplies(from output: FileHandle) async {
        // A read error means the process is gone: ending the turn is the signal.
        do {
            for try await line in output.bytes.lines {
                switch ClaudeCodeStream.parse(line: line) {
                case .textDelta(let text): currentTurn.withLock { _ = $0?.yield(text) }
                case .finished: endTurn()
                case nil: break
                }
            }
        } catch {}
        endTurn()
    }

    private func endTurn() {
        currentTurn.withLock { $0?.finish(); $0 = nil }
    }

    /// Sends one user turn; the stream yields the reply's text deltas and ends with the turn.
    public func ask(_ text: String) throws -> AsyncStream<String> {
        let (reply, continuation) = AsyncStream<String>.makeStream()
        currentTurn.withLock { $0 = continuation }
        try input.fileHandleForWriting.write(contentsOf: ClaudeCodeStream.userMessage(text))
        return reply
    }

    public func stop() {
        process.terminate()
    }
}
