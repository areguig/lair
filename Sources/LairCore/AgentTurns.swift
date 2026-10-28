import Foundation
import Synchronization

/// Routes a local agent's events to the turn that is running. After an interrupt the old turn keeps
/// flushing until its end, so everything is dropped until then.
final class AgentTurns: Sendable {
    private struct State {
        var reply: AsyncThrowingStream<AgentReply, Error>.Continuation?
        var running = false
        var draining = false
    }

    private let state = Mutex(State())

    func begin() -> AsyncThrowingStream<AgentReply, Error> {
        let (reply, continuation) = AsyncThrowingStream<AgentReply, Error>.makeStream()
        state.withLock {
            $0.reply = continuation
            $0.running = true
        }
        return reply
    }

    func receive(_ event: AgentEvent) {
        state.withLock { state in
            if state.draining {
                switch event {
                case .finished, .failed: state.draining = false
                default: break
                }
                return
            }
            switch event {
            case .textDelta(let text): state.reply?.yield(.text(text))
            case .approval(let request): state.reply?.yield(.approval(request))
            case .finished:
                state.reply?.finish()
                state.reply = nil
                state.running = false
            case .failed(let message):
                state.reply?.finish(throwing: AgentFailure(message: message))
                state.reply = nil
                state.running = false
            }
        }
    }

    /// Ends the current turn here; returns whether Claude Code must be told to stop it too.
    func interrupt() -> Bool {
        state.withLock { state in
            state.reply?.finish()
            state.reply = nil
            guard state.running else { return false }
            state.running = false
            state.draining = true
            return true
        }
    }

    /// The process is gone; a turn still waiting on it fails with `AgentStopped`.
    func close() {
        state.withLock { state in
            state.reply?.finish(throwing: AgentStopped())
            state = State()
        }
    }
}

/// An agent reported that its turn failed.
public struct AgentFailure: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
}
