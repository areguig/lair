import Foundation

/// A live conversation with one agent; a call keeps one for its whole length.
public protocol AgentSession: Sendable {
    /// Sends one user turn; the stream yields the reply as it comes and ends with the turn.
    func ask(_ text: String) throws -> AsyncThrowingStream<AgentReply, Error>
    /// Answers an approval the current turn is waiting on.
    func answer(_ request: ApprovalRequest, decision: ApprovalDecision) throws
    /// Stops the reply in progress; the current `ask` stream ends.
    func interrupt()
    func stop()
    /// What runs the agent, e.g. "gpt-6-luna · low thinking", as soon as the agent tells.
    var details: AsyncStream<String> { get }
    /// Work the agent finished in the background after the turn that started it ended.
    var news: AsyncStream<String> { get }
}

extension AgentSession {
    public func answer(_ request: ApprovalRequest, decision: ApprovalDecision) throws {}
    public var details: AsyncStream<String> { AsyncStream { $0.finish() } }
    public var news: AsyncStream<String> { AsyncStream { $0.finish() } }
}

/// "gpt-6-luna" and "low" → "gpt-6-luna · low thinking".
public func agentDetails(model: String?, thinking: String?) -> String? {
    let parts = [model, thinking.flatMap { $0 == "off" || $0.isEmpty ? nil : "\($0) thinking" }].compactMap { $0 }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
}

public enum AgentReply: Equatable, Sendable {
    case text(String)
    /// The agent is paused until `answer` is called.
    case approval(ApprovalRequest)
}

public enum ApprovalDecision: Equatable, Sendable {
    case allowOnce, allowAlways, deny
}

/// Something the agent wants to do that needs a yes or no from you.
public struct ApprovalRequest: Equatable, Identifiable, Sendable {
    public let id: String
    public let tool: String
    /// What the agent says the action does, in words that can be read aloud.
    public let summary: String
    /// The tool's input as the agent sent it, returned unchanged when allowed.
    let input: Data
    /// The agent's `permission_suggestions` JSON array, sent back to make an allow permanent.
    let suggestions: Data?

    public var canAlwaysAllow: Bool {
        guard let suggestions, let list = try? JSONSerialization.jsonObject(with: suggestions) as? [Any] else { return false }
        return !list.isEmpty
    }

    public init(id: String, tool: String, summary: String, input: Data = Data("{}".utf8), suggestions: Data? = nil) {
        self.id = id
        self.tool = tool
        self.summary = summary
        self.input = input
        self.suggestions = suggestions
    }
}
