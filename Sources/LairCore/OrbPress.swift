/// What a press on the floating orb means: a click toggles talking, holding talks until you let go,
/// a double-click opens Lair, and dragging moves the orb.
/// `.wait` asks the caller to send `.timeout` after the double-click interval, replacing any earlier wait.
public struct OrbPress {
    public enum Input: Equatable {
        case down(clicks: Int), moved, up, timeout
    }

    public enum Effect: Equatable {
        case wait, startHold, endHold, toggleTalk, openPanel, drag
    }

    private enum Phase {
        case idle, pressed, holding, clicked, done
    }

    private var phase = Phase.idle

    public init() {}

    public mutating func handle(_ input: Input) -> Effect? {
        switch (phase, input) {
        case (_, .down(let clicks)) where clicks > 1:
            phase = .done
            return .openPanel
        case (.idle, .down), (.clicked, .down):
            phase = .pressed
            return .wait
        case (.pressed, .moved):
            phase = .done
            return .drag
        case (.pressed, .timeout):
            phase = .holding
            return .startHold
        case (.pressed, .up):
            phase = .clicked
            return .wait
        case (.holding, .up):
            phase = .idle
            return .endHold
        case (.clicked, .timeout):
            phase = .idle
            return .toggleTalk
        case (.done, .up):
            phase = .idle
            return nil
        default:
            return nil
        }
    }
}
