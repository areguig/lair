import Foundation

/// Listening for your reply without a key press, for a few seconds after the agent speaks.
public enum FollowUp {
    /// Decides, as the microphone hears speech or silence, when you've said your piece.
    public struct Turn: Sendable {
        public enum Decision: Equatable, Sendable { case listen, send, giveUp }

        /// How long Lair waits for you to start.
        public static let patience: Duration = .seconds(5)
        /// The longest answer before it's sent anyway.
        public static let longest: Duration = .seconds(30)
        /// Shorter bursts (a cough, a click) don't count as an answer.
        public static let shortest: Duration = .milliseconds(300)

        private var speechStart: Duration?
        private var heard = false

        public init() {}

        /// `speaking` is what the voice detector hears now; `elapsed` is the time since listening began.
        public mutating func update(speaking: Bool, elapsed: Duration) -> Decision {
            if speaking {
                if speechStart == nil { speechStart = elapsed }
                if let start = speechStart, elapsed - start >= Self.shortest { heard = true }
            } else if speechStart != nil {
                speechStart = nil
                if heard { return .send }
            }
            if elapsed >= Self.longest { return heard ? .send : .giveUp }
            if !heard, speechStart == nil, elapsed >= Self.patience { return .giveUp }
            return .listen
        }
    }
}
