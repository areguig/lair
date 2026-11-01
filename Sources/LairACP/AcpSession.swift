import Foundation
import LairCore
import Synchronization

/// A call with any agent that speaks the Agent Client Protocol.
///
/// Your turn is a `session/prompt` request: what the agent sends while it runs answers you. What it sends with no
/// prompt running, such as the result of background work, is a turn of its own; ACP v1 marks no end for those, so
/// one ends after `ownTurnQuiet` without news, or when you speak.
public final class AcpSession: AgentSession {
    public struct Settings: Sendable {
        /// The folder the agent works in.
        public var directory: String
        /// Said once, before your first message: who the agent is on this call and how to talk by voice.
        public var preamble: String?
        public var mcpServers: [MCPServer]
        public var ownTurnQuiet: Duration

        public init(directory: String, preamble: String?, mcpServers: [MCPServer] = [], ownTurnQuiet: Duration) {
            (self.directory, self.preamble, self.mcpServers, self.ownTurnQuiet) = (directory, preamble, mcpServers, ownTurnQuiet)
        }
    }

    /// An MCP server the agent connects to for the call.
    public struct MCPServer: Sendable, Equatable {
        public var name: String
        public var url: URL
        public var headers: [String: String]

        public init(name: String, url: URL, headers: [String: String] = [:]) {
            (self.name, self.url, self.headers) = (name, url, headers)
        }
    }

    private struct State {
        var sessionID: String?
        var prompt: Prompt?
        var own: AgentTurn.Continuation?
        /// Bumped by every update to an own turn, so only the last one's quiet timer ends it.
        var ownNews = 0
        var options: [ACPWire.ConfigOption] = []
        var approvals: [String: (id: JSONRPCID, options: [ACPWire.PermissionOption])] = [:]
        var preambleSent = false
    }

    /// The prompt running; once interrupted its reply is gone and what the agent still sends for it is dropped.
    private struct Prompt {
        let id: UUID
        var reply: AgentTurn.Continuation?
    }

    private let peer: JSONRPCPeer
    private let channel: LineChannel
    private let settings: Settings
    private let state = Mutex(State())
    private let setup: Task<ACPWire.NewSessionResult, Error>
    public let ownTurns: AsyncStream<AgentTurn>
    private let ownTurnsContinuation: AsyncStream<AgentTurn>.Continuation
    public let details: AsyncStream<String>
    private let detailsContinuation: AsyncStream<String>.Continuation
    public let models: AsyncStream<[String]>
    private let modelsContinuation: AsyncStream<[String]>.Continuation
    public let problems: AsyncStream<String>
    private let problemsContinuation: AsyncStream<String>.Continuation

    public init(channel: LineChannel, settings: Settings) {
        self.channel = channel
        self.settings = settings
        let peer = JSONRPCPeer(channel: channel)
        self.peer = peer
        (ownTurns, ownTurnsContinuation) = AsyncStream<AgentTurn>.makeStream()
        (details, detailsContinuation) = AsyncStream<String>.makeStream()
        (models, modelsContinuation) = AsyncStream<[String]>.makeStream()
        (problems, problemsContinuation) = AsyncStream<String>.makeStream()
        setup = Task {
            _ = try await peer.request("initialize", ACPWire.InitializeParams(clientInfo: .init(name: "Lair", version: "1")),
                                       as: ACPWire.InitializeResult.self)
            let servers = settings.mcpServers.map { server in
                ACPWire.MCPServer(name: server.name, url: server.url.absoluteString,
                                  headers: server.headers.sorted { $0.key < $1.key }.map { .init(name: $0.key, value: $0.value) })
            }
            return try await peer.request("session/new", ACPWire.NewSessionParams(cwd: settings.directory, mcpServers: servers),
                                          as: ACPWire.NewSessionResult.self)
        }
        Task { [self] in
            do {
                let session = try await setup.value
                state.withLock { $0.sessionID = session.sessionId }
                show(session.configOptions)
            } catch {
                problemsContinuation.yield("Couldn't start the call: \(error.localizedDescription)")
            }
        }
        peer.start(handle: { [self] in receive($0) }, closed: { [self] in closeTurns() })
    }

    // MARK: Turns

    public func ask(_ text: String) throws -> AgentTurn {
        let (reply, continuation) = AgentTurn.makeStream()
        let id = UUID()
        let preamble = state.withLock { state -> String? in
            // Speaking ends the agent's own turn: what comes next answers you.
            state.own?.finish()
            state.own = nil
            state.prompt = Prompt(id: id, reply: continuation)
            defer { state.preambleSent = true }
            return state.preambleSent ? nil : settings.preamble
        }
        Task { [self] in
            do {
                let sessionID = try await setup.value.sessionId
                let blocks = [preamble, text].compactMap { $0 }.map { ACPWire.TextBlock(text: $0) }
                // Ended in reading order, so what the agent sends right after its answer is a turn of its own.
                peer.request("session/prompt", ACPWire.PromptParams(sessionId: sessionID, prompt: blocks)) { [self] answer in
                    finishPrompt(id) { reply in Self.end(reply, with: answer) }
                }
            } catch {
                finishPrompt(id) { $0.finish(throwing: error) }
            }
        }
        return reply
    }

    private static func end(_ reply: AgentTurn.Continuation, with answer: Result<Data, Error>) {
        do {
            let result = try JSONDecoder().decode(ACPWire.PromptResult.self, from: answer.get())
            if let usage = result.usage {
                reply.yield(.activity(.usage(
                    inputTokens: (usage.inputTokens ?? 0) + (usage.cachedReadTokens ?? 0) + (usage.cachedWriteTokens ?? 0),
                    outputTokens: usage.outputTokens ?? 0, cost: nil)))
            }
            guard result.stopReason != "refusal" else { throw AgentFailure(message: "The agent refused to continue.") }
            reply.finish()
        } catch {
            reply.finish(throwing: error)
        }
    }

    private func finishPrompt(_ id: UUID, _ finish: (AgentTurn.Continuation) -> Void) {
        let reply = state.withLock { state -> AgentTurn.Continuation? in
            guard state.prompt?.id == id else { return nil }
            defer { state.prompt = nil }
            return state.prompt?.reply
        }
        reply.map(finish)
    }

    /// Stops the reply being heard: the prompt is cancelled and its approvals answered as cancelled; an own turn
    /// can't be stopped in ACP v1, so it's only no longer heard.
    public func interrupt() {
        let (sessionID, approvals) = state.withLock { state in
            state.prompt?.reply?.finish()
            state.prompt?.reply = nil
            state.own?.finish()
            state.own = nil
            defer { state.approvals = [:] }
            return (state.prompt == nil ? nil : state.sessionID, state.approvals.values.map(\.id))
        }
        for id in approvals { try? peer.respond(to: id, with: ACPWire.PermissionResult.cancelled) }
        if let sessionID { try? peer.notify("session/cancel", ACPWire.SessionParams(sessionId: sessionID)) }
    }

    public func stop() {
        setup.cancel()
        channel.close()
    }

    private func closeTurns() {
        state.withLock { state in
            state.prompt?.reply?.finish(throwing: AgentStopped())
            state.prompt = nil
            state.own?.finish()
            state.own = nil
        }
        ownTurnsContinuation.finish()
        detailsContinuation.finish()
        modelsContinuation.finish()
        problemsContinuation.finish()
    }

    // MARK: What the agent sends

    private func receive(_ message: JSONRPCPeer.Incoming) {
        switch message {
        case .notification("session/update", let params):
            guard let notification = try? JSONDecoder().decode(ACPWire.SessionNotification.self, from: params) else { return }
            switch notification.update {
            case .agentText(let text): deliver(.text(text))
            case .agentThought(let text): deliver(.activity(.thinking(text)))
            case .toolCall(let id, let title, let input):
                deliver(.activity(.toolStarted(id: id, name: title, input: Activity.trimmed(input, limit: 200))))
            case .toolCallUpdate(let id, let status, let output):
                guard status == "completed" || status == "failed" else { return }
                deliver(.activity(.toolFinished(id: id, output: Activity.trimmed(output), failed: status == "failed")))
            case .configOptions(let options):
                show(options)
            case .other:
                break
            }
        case .request(let id, "session/request_permission", let params):
            guard let request = try? JSONDecoder().decode(ACPWire.PermissionRequest.self, from: params) else {
                try? peer.respond(to: id, with: JSONRPCError(code: -32602, message: "Invalid params"))
                return
            }
            let summary = request.toolCall.title ?? "use a tool"
            let approval = ApprovalRequest(id: "\(id)", tool: summary, summary: summary,
                                           canAlwaysAllow: request.options.contains { $0.kind == "allow_always" })
            state.withLock { $0.approvals[approval.id] = (id, request.options) }
            deliver(.approval(approval))
        case .request(let id, let method, _):
            try? peer.respond(to: id, with: JSONRPCError.methodNotFound(method))
        case .notification:
            break
        }
    }

    /// To the prompt running; with none, to the agent's own turn, started if needed.
    private func deliver(_ reply: AgentReply) {
        let ownNews = state.withLock { state -> Int? in
            if let prompt = state.prompt {
                prompt.reply?.yield(reply)
                return nil
            }
            if state.own == nil {
                let (turn, continuation) = AgentTurn.makeStream()
                state.own = continuation
                ownTurnsContinuation.yield(turn)
            }
            state.own?.yield(reply)
            state.ownNews += 1
            return state.ownNews
        }
        guard let ownNews else { return }
        Task { [self] in
            try? await Task.sleep(for: settings.ownTurnQuiet)
            state.withLock { state in
                guard state.ownNews == ownNews else { return }
                state.own?.finish()
                state.own = nil
            }
        }
    }

    public func answer(_ request: ApprovalRequest, decision: ApprovalDecision) throws {
        guard let pending = state.withLock({ $0.approvals.removeValue(forKey: request.id) }) else { return }
        let preferred: [String] = switch decision {
        case .allowOnce: ["allow_once", "allow_always"]
        case .allowAlways: ["allow_always", "allow_once"]
        case .deny: ["reject_once", "reject_always"]
        }
        guard let option = preferred.lazy.compactMap({ kind in pending.options.first { $0.kind == kind } }).first else {
            return try peer.respond(to: pending.id, with: ACPWire.PermissionResult.cancelled)
        }
        try peer.respond(to: pending.id, with: ACPWire.PermissionResult.selected(option.optionId))
    }

    // MARK: Model and thinking

    public var thinkingLevels: [String] {
        state.withLock { $0.options.first { $0.category == "thought_level" }?.values.map(\.name) ?? [] }
    }

    public func setModel(_ model: String) throws {
        try set(category: "model", to: model)
    }

    public func setThinking(_ level: String) throws {
        try set(category: "thought_level", to: level)
    }

    /// Picks the value by its id or name, exactly, else the first that contains it ("opus" → "Claude Opus 5.5").
    private func set(category: String, to wanted: String) throws {
        let (sessionID, option) = state.withLock { ($0.sessionID, $0.options.first { $0.category == category }) }
        guard let sessionID, let option else { throw ChangeLater() }
        let matches = { (value: ACPWire.ConfigOption.Value) in
            value.value.caseInsensitiveCompare(wanted) == .orderedSame || value.name.caseInsensitiveCompare(wanted) == .orderedSame
        }
        guard let value = option.values.first(where: matches)
            ?? option.values.first(where: { $0.name.localizedCaseInsensitiveContains(wanted) || $0.value.localizedCaseInsensitiveContains(wanted) })
        else { throw AgentFailure(message: "The agent has no \(option.name.lowercased()) called \(wanted).") }
        Task { [self] in
            do {
                let result = try await peer.request("session/set_config_option",
                                                    ACPWire.SetConfigOptionParams(sessionId: sessionID, configId: option.id, value: value.value),
                                                    as: ACPWire.ConfigOptionsResult.self)
                show(result.configOptions)
            } catch {
                problemsContinuation.yield("Couldn't change the \(option.name.lowercased()): \(error.localizedDescription)")
            }
        }
    }

    /// Keeps the agent's options and tells which model and thinking level it runs.
    private func show(_ options: [ACPWire.ConfigOption]) {
        state.withLock { $0.options = options }
        let current = { (category: String) in
            options.first { $0.category == category }.flatMap { option in option.values.first { $0.value == option.currentValue }?.name }
        }
        if let model = options.first(where: { $0.category == "model" }) { modelsContinuation.yield(model.values.map(\.name)) }
        if let details = agentDetails(model: current("model"), thinking: current("thought_level")) { detailsContinuation.yield(details) }
    }
}
