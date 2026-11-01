import Foundation

/// What a local agent's output says, in the agent's own order.
public enum AgentEvent: Equatable, Sendable {
    case textDelta(String)
    case approval(ApprovalRequest)
    /// The agent took in your message: what it says next answers it.
    case yourMessage
    /// The turn is over.
    case finished(String)
    case failed(String)
    /// The agent stopped working; ends a turn it started itself. Agents that report your turn's end apart
    /// (omp's `prompt_result`) send this for every run.
    case idle
    /// Which model and thinking level the agent runs.
    case details(String)
    case activity(Activity)
}
