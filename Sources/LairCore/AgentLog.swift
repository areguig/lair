import Foundation

/// Where an agent's own error output goes, one file per agent, overwritten on each call.
public enum AgentLog {
    public static func url(for agentID: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/Lair/\(agentID).log")
    }

    /// The first thing the agent printed, which usually says why it stopped.
    public static func firstLine(for agentID: String) -> String? {
        guard let text = try? String(contentsOf: url(for: agentID), encoding: .utf8) else { return nil }
        return text.split(whereSeparator: \.isNewline).first.map(String.init)
    }

    static func handle(for url: URL?) -> FileHandle {
        guard let url else { return .nullDevice }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        return (try? FileHandle(forWritingTo: url)) ?? .nullDevice
    }
}

/// The agent's process has exited; whatever it printed is in its log.
public struct AgentStopped: Error {}
