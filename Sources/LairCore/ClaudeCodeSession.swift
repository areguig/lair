import Foundation

/// One long-lived `claude -p` process per call, so only the first turn pays for its startup.
public final class ClaudeCodeSession: AgentSession {
    private let process = Process()
    private let input = Pipe()
    private let turns = AgentTurns()
    public let details: AsyncStream<String>
    private let detailsContinuation: AsyncStream<String>.Continuation

    /// `permissionMode` nil keeps your Claude Code settings; whatever they would ask you about comes to Lair.
    public var models: AsyncStream<[String]> {
        AsyncStream { $0.yield(["opus", "sonnet", "haiku"]); $0.finish() }
    }
    /// Claude Code's effort; it only changes from the next call.
    public let thinkingLevels = ["low", "medium", "high", "xhigh", "max"]

    public init(model: String? = nil, effort: String? = nil, directory: URL? = nil,
                environment: [String: String]? = nil, permissionMode: String? = nil, errorLog: URL? = nil,
                systemPrompt: String = VoicePrompt.text) throws {
        (details, detailsContinuation) = AsyncStream<String>.makeStream()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.currentDirectoryURL = directory
        if let environment { process.environment = environment }
        process.arguments = ["claude", "-p", "--input-format", "stream-json", "--output-format", "stream-json",
                             "--verbose", "--include-partial-messages", "--no-session-persistence",
                             "--permission-prompt-tool", "stdio", "--append-system-prompt", systemPrompt]
            + (model.map { ["--model", $0] } ?? [])
            + (permissionMode.map { ["--permission-mode", $0] } ?? [])
            + (effort.map { ["--effort", $0] } ?? [])
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = AgentLog.handle(for: errorLog)
        try AgentLog.run(process)
        Task { await routeReplies(from: output.fileHandleForReading) }
    }

    private func routeReplies(from output: FileHandle) async {
        // A read error means the process is gone: closing the turns is the signal.
        do {
            for try await line in output.bytes.lines {
                AgentLog.stray(line)
                for event in ClaudeCodeStream.parseAll(line: line) {
                    if case .details(let text) = event { detailsContinuation.yield(text) } else { turns.receive(event) }
                }
            }
        } catch {}
        turns.close()
        detailsContinuation.finish()
    }

    public func ask(_ text: String) throws -> AsyncThrowingStream<AgentReply, Error> {
        let reply = turns.begin()
        try send(ClaudeCodeStream.userMessage(text))
        return reply
    }

    public func answer(_ request: ApprovalRequest, decision: ApprovalDecision) throws {
        try send(ClaudeCodeStream.approvalResponse(request, decision: decision))
    }

    public func setModel(_ model: String) throws {
        try send(ClaudeCodeStream.setModelRequest(model))
    }

    public func interrupt() {
        guard turns.interrupt() else { return }
        try? send(ClaudeCodeStream.interruptRequest())
    }

    public func stop() {
        process.terminate()
    }

    private func send(_ line: Data) throws {
        guard process.isRunning else { throw AgentStopped() }
        try input.fileHandleForWriting.write(contentsOf: line)
    }
}
