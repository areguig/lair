import Foundation

/// A live conversation with one agent; a call keeps one for its whole length.
public protocol AgentSession: Sendable {
    /// Sends one user turn; the stream yields the reply as it comes and ends with the turn.
    func ask(_ text: String) throws -> AsyncThrowingStream<AgentReply, Error>
    /// Answers an approval the current turn is waiting on.
    func answer(_ request: ApprovalRequest, allow: Bool) throws
    func stop()
}

extension AgentSession {
    public func answer(_ request: ApprovalRequest, allow: Bool) throws {}
}

public enum AgentReply: Equatable, Sendable {
    case text(String)
    /// The agent is paused until `answer` is called.
    case approval(ApprovalRequest)
}

/// Something the agent wants to do that needs a yes or no from you.
public struct ApprovalRequest: Equatable, Identifiable, Sendable {
    public let id: String
    public let tool: String
    /// What the agent says the action does, in words that can be read aloud.
    public let summary: String
    /// The tool's input as the agent sent it, returned unchanged when allowed.
    let input: Data

    public init(id: String, tool: String, summary: String, input: Data = Data("{}".utf8)) {
        self.id = id
        self.tool = tool
        self.summary = summary
        self.input = input
    }
}
