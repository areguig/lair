import Foundation
import LairACP
import LairCore
import LairMCP
import LairVoice
import Observation
import os

/// One agent you can call; while in a call it holds a live session.
@Observable @MainActor final class Call: @MainActor Identifiable {
    typealias State = CallState

    struct Line: Identifiable {
        /// `info` is what Lair tells you along the way; `problem` is something that went wrong.
        enum Role { case you, agent, info, problem }
        /// A button next to a line, so a problem comes with its way out.
        enum Action: Equatable { case openSettings, showLog(agentID: String) }
        let id = UUID()
        let role: Role
        var text: String
        var action: Action?
        /// Links, paths and commands the agent showed instead of saying (`<show>…</show>`), where they sit in the text.
        var shown: [Shown] = []
    }

    var agent: AgentConfig
    var state = State.offline {
        didSet { if state == .ready, oldValue != .ready { becameReady?() } }
    }
    /// Set by the room, so a turn the agent took by itself is heard as soon as the call is free, however it got free.
    @ObservationIgnored var becameReady: (@MainActor () -> Void)?
    var lines: [Line] = []
    var pendingApproval: ApprovalRequest?
    /// Finished or needs you while you were talking to someone else.
    var unread = false
    /// Model and thinking level, once the agent says.
    var details: String?
    /// Models the agent offers on this call, once it lists them.
    var models: [String] = []
    /// The thinking level this call runs at, as last set.
    var thinking: String?
    /// A thinking level asked for mid-call that the agent can only take from its next call.
    @ObservationIgnored var thinkingNextCall: String?
    /// What the agent said while another agent had the floor, heard when you switch to it.
    @ObservationIgnored var unheard: [String] = []
    /// The whole exchange for Mission Control; kept across calls with this agent until Lair quits.
    var entries: [LogEntry] = []
    @ObservationIgnored var session: (any AgentSession)?
    @ObservationIgnored var turn: Task<Void, Never>?
    /// Identifies the running turn, so an interrupted one can't reset the state of the next.
    @ObservationIgnored var turnID: UUID?
    /// Turns the agent took by itself while the call was busy, oldest first; heard as soon as it's ready.
    @ObservationIgnored var ownTurnsWaiting: [AgentTurn] = []
    /// What other agents answered for this one while you talked to them; sent before its next turn.
    @ObservationIgnored var context: [String] = []
    /// The session you started yourself on this Mac that this call is, while it's connected.
    var visitor: Guest?
    /// Driven by a session on this Mac: it speaks and asks on its own, you only answer.
    var guest: Bool { visitor != nil || stranger }
    /// A session that matches none of your agents: it's in the room only while it's connected.
    var stranger: Bool { agent.kind == .guest }
    /// A visitor's working folder, as it told Lair.
    var folder: URL?
    /// When a guest last said anything; quiet ones leave.
    @ObservationIgnored var heard = Date.distantPast
    /// A guest's question waiting for your answer, with what it asked and until when it waits.
    @ObservationIgnored var question: CheckedContinuation<String?, Never>?
    var questionText: String?
    /// The options it offered, shown as buttons; empty for an open question.
    var questionChoices: [String] = []
    var questionSince: Date?
    var questionDeadline: Date?

    /// Paused on something only you can give: an OK, or a guest's answer.
    var awaitsYou: Bool { pendingApproval != nil || questionText != nil }
    var idle: State { awaitsYou ? .waiting : .ready }

    init(agent: AgentConfig) {
        self.agent = agent
    }

    var id: String { agent.id }
    var inCall: Bool { state != .offline }
}
