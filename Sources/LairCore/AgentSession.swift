/// A live conversation with one agent; a call keeps one for its whole length.
public protocol AgentSession: Sendable {
    /// Sends one user turn; the stream yields the reply's text as it comes and ends with the turn.
    func ask(_ text: String) throws -> AsyncThrowingStream<String, Error>
    func stop()
}
