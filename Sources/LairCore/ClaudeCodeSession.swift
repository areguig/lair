import Foundation
import Synchronization

/// One long-lived `claude -p` process per call, so only the first turn pays for its startup.
public final class ClaudeCodeSession: AgentSession {
    private let process = Process()
    private let input = Pipe()
    private let currentTurn = Mutex<AsyncThrowingStream<AgentReply, Error>.Continuation?>(nil)

    /// `permissionMode` nil keeps your Claude Code settings; whatever they would ask you about comes to Lair.
    public init(model: String? = nil, directory: URL? = nil, environment: [String: String]? = nil,
                permissionMode: String? = nil, systemPrompt: String = VoicePrompt.text) throws {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.currentDirectoryURL = directory
        if let environment { process.environment = environment }
        process.arguments = ["claude", "-p", "--input-format", "stream-json", "--output-format", "stream-json",
                             "--verbose", "--include-partial-messages", "--no-session-persistence",
                             "--permission-prompt-tool", "stdio", "--append-system-prompt", systemPrompt]
            + (model.map { ["--model", $0] } ?? [])
            + (permissionMode.map { ["--permission-mode", $0] } ?? [])
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
                case .textDelta(let text): currentTurn.withLock { _ = $0?.yield(.text(text)) }
                case .approval(let request): currentTurn.withLock { _ = $0?.yield(.approval(request)) }
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

    public func ask(_ text: String) throws -> AsyncThrowingStream<AgentReply, Error> {
        let (reply, continuation) = AsyncThrowingStream<AgentReply, Error>.makeStream()
        currentTurn.withLock { $0 = continuation }
        try input.fileHandleForWriting.write(contentsOf: ClaudeCodeStream.userMessage(text))
        return reply
    }

    public func answer(_ request: ApprovalRequest, allow: Bool) throws {
        try input.fileHandleForWriting.write(contentsOf: ClaudeCodeStream.approvalResponse(request, allow: allow))
    }

    public func stop() {
        process.terminate()
    }
}
