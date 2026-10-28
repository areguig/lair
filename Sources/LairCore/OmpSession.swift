import Foundation

/// One `omp --mode rpc` process per call, run directly (no omp-relay) and not saved as an omp session.
public final class OmpSession: AgentSession {
    private let process = Process()
    private let input = Pipe()
    private let turns = AgentTurns()
    public let details: AsyncStream<String>
    private let detailsContinuation: AsyncStream<String>.Continuation

    public init(model: String? = nil, directory: URL? = nil, environment: [String: String]? = nil,
                errorLog: URL? = nil, systemPrompt: String = VoicePrompt.text) throws {
        (details, detailsContinuation) = AsyncStream<String>.makeStream()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.currentDirectoryURL = directory
        if let environment { process.environment = environment }
        process.arguments = ["omp", "--mode", "rpc", "--no-session", "--append-system-prompt", systemPrompt]
            + (model.map { ["--model", $0] } ?? [])
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = AgentLog.handle(for: errorLog)
        try process.run()
        try send(OmpStream.deltaUpdates())
        try send(OmpStream.getState())
        Task { await routeReplies(from: output.fileHandleForReading) }
    }

    private func routeReplies(from output: FileHandle) async {
        // A read error means the process is gone: closing the turns is the signal.
        do {
            for try await line in output.bytes.lines {
                switch OmpStream.parse(line: line) {
                case .event(.details(let text)): detailsContinuation.yield(text)
                case .event(let event): turns.receive(event)
                case .stateChanged: try? send(OmpStream.getState())
                case .unsupportedDialog(let id): try? send(OmpStream.cancelDialog(id: id))
                case nil: break
                }
            }
        } catch {}
        turns.close()
        detailsContinuation.finish()
    }

    public func ask(_ text: String) throws -> AsyncThrowingStream<AgentReply, Error> {
        let reply = turns.begin()
        try send(OmpStream.prompt(text, id: "lair-\(UUID().uuidString)"))
        return reply
    }

    public func answer(_ request: ApprovalRequest, decision: ApprovalDecision) throws {
        try send(OmpStream.confirm(request, decision: decision))
    }

    public func interrupt() {
        guard turns.interrupt() else { return }
        try? send(OmpStream.abort())
    }

    public func stop() {
        process.terminate()
    }

    private func send(_ line: Data) throws {
        guard process.isRunning else { throw AgentStopped() }
        try input.fileHandleForWriting.write(contentsOf: line)
    }
}
