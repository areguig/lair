import Foundation
import Synchronization

/// Routes a local agent's events to the turn they belong to. Your turn starts when the agent takes in your
/// message; whatever the agent says with no turn open is a turn it started itself, published on `ownTurns`.
final class AgentTurns: Sendable {
    private struct Turn {
        let reply: AgentTurn.Continuation
        let own: Bool
    }

    private struct State {
        var current: Turn?
        /// Asked, not yet taken in by the agent; nil once interrupted, so its events are dropped.
        var asked: [AgentTurn.Continuation?] = []
        var draining = false
    }

    private let state = Mutex(State())
    let ownTurns: AsyncStream<AgentTurn>
    private let ownTurnsContinuation: AsyncStream<AgentTurn>.Continuation

    init() {
        (ownTurns, ownTurnsContinuation) = AsyncStream<AgentTurn>.makeStream()
    }

    func begin() -> AgentTurn {
        let (reply, continuation) = AgentTurn.makeStream()
        state.withLock { $0.asked.append(continuation) }
        return reply
    }

    func receive(_ event: AgentEvent) {
        state.withLock { state in
            if case .yourMessage = event { return takeIn(&state) }
            if state.draining {
                switch event {
                case .finished, .failed, .idle: state.draining = false
                default: break
                }
                return
            }
            switch event {
            case .finished:
                state.current?.reply.finish()
                state.current = nil
            case .idle:
                guard state.current?.own == true else { return }
                state.current?.reply.finish()
                state.current = nil
            case .failed(let message):
                let failure = AgentFailure(message: message)
                if let current = state.current {
                    current.reply.finish(throwing: failure)
                    state.current = nil
                } else if !state.asked.isEmpty {
                    // Refused before the agent took it in.
                    state.asked.removeFirst()?.finish(throwing: failure)
                }
            case .textDelta(let text): reply(&state).yield(.text(text))
            case .approval(let request): reply(&state).yield(.approval(request))
            case .activity(let activity): reply(&state).yield(.activity(activity))
            case .details, .yourMessage: break
            }
        }
    }

    /// Ends the turn being heard, and any asked turn not yet taken in; returns whether the agent must be told to
    /// stop too.
    func interrupt() -> Bool {
        state.withLock { state in
            let waiting = state.asked.contains { $0 != nil }
            for index in state.asked.indices {
                state.asked[index]?.finish()
                state.asked[index] = nil
            }
            guard let current = state.current else { return waiting }
            current.reply.finish()
            state.current = nil
            state.draining = true
            return true
        }
    }

    /// The process is gone; every turn still open fails with `AgentStopped`.
    func close() {
        state.withLock { state in
            state.current?.reply.finish(throwing: AgentStopped())
            for reply in state.asked { reply?.finish(throwing: AgentStopped()) }
            state = State()
        }
        ownTurnsContinuation.finish()
    }

    /// The agent took in your oldest message: what it says next answers it, even mid-way through its own turn.
    private func takeIn(_ state: inout State) {
        state.current?.reply.finish()
        state.current = nil
        state.draining = false
        guard !state.asked.isEmpty else { return }
        if let reply = state.asked.removeFirst() {
            state.current = Turn(reply: reply, own: false)
        } else {
            state.draining = true
        }
    }

    private func reply(_ state: inout State) -> AgentTurn.Continuation {
        if let current = state.current { return current.reply }
        let (turn, reply) = AgentTurn.makeStream()
        state.current = Turn(reply: reply, own: true)
        ownTurnsContinuation.yield(turn)
        return reply
    }
}

/// An agent reported that its turn failed.
public struct AgentFailure: LocalizedError {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}
