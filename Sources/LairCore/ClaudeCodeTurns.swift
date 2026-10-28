import Synchronization

/// Routes Claude Code's events to the turn that is running. After an interrupt the old turn keeps
/// flushing until its `result`, so everything is dropped until then.
final class ClaudeCodeTurns: Sendable {
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
                if case .finished = event { state.draining = false }
                return
            }
            switch event {
            case .textDelta(let text): state.reply?.yield(.text(text))
            case .approval(let request): state.reply?.yield(.approval(request))
            case .finished:
                state.reply?.finish()
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

    /// The process is gone.
    func close() {
        state.withLock { state in
            state.reply?.finish()
            state = State()
        }
    }
}
