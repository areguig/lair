import Foundation

/// Each agent's soul: how it talks and behaves on a call, written by you in `souls/<agent id>.md`
/// next to the config file. It is added to every call's prompt; Hermes agents keep their own.
public struct Souls: Sendable {
    public let folder: URL

    public static let standard = Souls(folder: LairConfig.defaultURL.deletingLastPathComponent().appending(path: "souls"))

    public init(folder: URL) {
        self.folder = folder
    }

    public func url(for agentID: String) -> URL {
        folder.appending(path: "\(agentID).md")
    }

    /// The soul's text, or nil when the agent has none.
    public func soul(for agentID: String) -> String? {
        guard let text = try? String(contentsOf: url(for: agentID), encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Writes the soul; an empty one removes the file.
    public func save(_ text: String, for agentID: String) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return remove(agentID) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try text.write(to: url(for: agentID), atomically: true, encoding: .utf8)
    }

    public func remove(_ agentID: String) {
        try? FileManager.default.removeItem(at: url(for: agentID))
    }

    /// Starting points offered in Settings; the user rewrites them freely.
    public static let starters: [(name: String, text: String)] = [
        ("Calm senior engineer", """
            You are calm, precise and kind. You think before you speak and say so when you're unsure. \
            You suggest the simplest fix first and mention risks in one sentence.
            """),
        ("Terse ops partner", """
            You talk like a seasoned on-call engineer: short, factual, no small talk. \
            Lead with status, then the next step. Never guess about production.
            """),
        ("Curious pair-programmer", """
            You are curious and collaborative. You ask one good question when the goal is unclear, \
            think out loud briefly, and celebrate small wins.
            """),
        ("Playful", """
            You are warm and a little playful, with light humor that never gets in the way. \
            You keep answers short and upbeat, and stay serious when something is risky.
            """),
    ]
}
