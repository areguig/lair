/// Where a call is. Every screen and the menu bar say it with the same words and symbol.
public enum CallState: Sendable, CaseIterable {
    case offline, ready, listening, thinking, speaking
    /// Paused on an approval only you can give.
    case waiting

    public var label: String {
        switch self {
        case .offline: "Not in a call"
        case .ready: "In a call"
        case .listening: "Listening"
        case .thinking: "Thinking"
        case .speaking: "Speaking"
        case .waiting: "Needs your OK"
        }
    }

    /// An SF Symbol name.
    public var symbol: String {
        switch self {
        case .offline: "phone.down"
        case .ready: "phone.fill"
        case .listening: "mic.fill"
        case .thinking: "ellipsis"
        case .speaking: "waveform"
        case .waiting: "hand.raised.fill"
        }
    }
}
