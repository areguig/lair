import Foundation
import Synchronization

/// One `omp --mode rpc` process per call, run directly (no omp-relay) and not saved as an omp session.
public final class OmpSession: AgentSession {
    private let process = Process()
    private let input = Pipe()
    private let turns = AgentTurns()
    public let details: AsyncStream<String>
    public let thinkingLevels = ["off", "minimal", "low", "medium", "high", "xhigh", "max"]
    private let available = Mutex<[OmpModel]>([])
    private let detailsContinuation: AsyncStream<String>.Continuation

    public init(model: String? = nil, thinking: String? = nil, directory: URL? = nil,
                environment: [String: String]? = nil, errorLog: URL? = nil,
                systemPrompt: String = VoicePrompt.text) throws {
        (details, detailsContinuation) = AsyncStream<String>.makeStream()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.currentDirectoryURL = directory
        if let environment { process.environment = environment }
        process.arguments = ["omp", "--mode", "rpc", "--no-session", "--append-system-prompt", systemPrompt]
            + (model.map { ["--model", $0] } ?? [])
            + (thinking.map { ["--thinking=\($0)"] } ?? [])
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = AgentLog.handle(for: errorLog)
        try process.run()
        try send(OmpStream.deltaUpdates())
        try send(OmpStream.getState())
        try send(OmpStream.getAvailableModels())
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
                case .models(let models): available.withLock { $0 = models }
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

    public var models: [String] { available.withLock { $0.map(\.id) } }

    /// Takes a model id from the list, or "provider/id".
    public func setModel(_ model: String) throws {
        let parts = model.split(separator: "/", maxSplits: 1).map(String.init)
        let choice: OmpModel? = parts.count == 2
            ? OmpModel(provider: parts[0], id: parts[1])
            : available.withLock { list in list.first { $0.id.caseInsensitiveCompare(model) == .orderedSame }
                ?? list.first { $0.id.localizedCaseInsensitiveContains(model) } }
        guard let choice else { throw AgentFailure(message: "omp has no model called \(model).") }
        try send(OmpStream.setModel(choice))
    }

    public func setThinking(_ level: String) throws {
        try send(OmpStream.setThinking(level))
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
