import Foundation

/// The sounds that go together on a switch in Settings.
public enum SoundGroup: String, Codable, CaseIterable, Sendable {
    case listening, done, needsYou, problems
}

/// How loud Lair's short sounds are and which kinds are off. Unset means everything on at full volume.
public struct SoundSettings: Codable, Equatable, Sendable {
    /// 0 to 1; unset means 1.
    public var volume: Double?
    /// The groups switched off; unset means none.
    public var off: [SoundGroup]?

    public init(volume: Double? = nil, off: [SoundGroup]? = nil) {
        self.volume = volume
        self.off = off
    }

    public var level: Double { min(max(volume ?? 1, 0), 1) }
    public var isDefault: Bool { level == 1 && (off ?? []).isEmpty }

    public func isOn(_ group: SoundGroup) -> Bool { !(off ?? []).contains(group) }

    /// Stores the default as unset, so the file only says what was changed.
    public mutating func set(_ group: SoundGroup, on: Bool) {
        let muted = SoundGroup.allCases.filter { $0 == group ? !on : !isOn($0) }
        off = muted.isEmpty ? nil : muted
    }

    public mutating func setLevel(_ level: Double) {
        let clamped = min(max(level, 0), 1)
        volume = clamped == 1 ? nil : clamped
    }
}
