/// An update found by a scheduled check waits for you; one you asked for, or have looked at, doesn't.
public struct UpdateReminder: Equatable, Sendable {
    public private(set) var version: String?

    public init() {}

    public mutating func found(_ version: String, userInitiated: Bool) {
        if !userInitiated { self.version = version }
    }

    public mutating func seen() {
        version = nil
    }
}
