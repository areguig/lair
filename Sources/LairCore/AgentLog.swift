import Foundation

/// Where an agent's own error output goes, one file per agent, overwritten on each call.
public enum AgentLog {
    public static func url(for agentID: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/Lair/\(agentID).log")
    }

    static func handle(for url: URL?) -> FileHandle {
        guard let url else { return .nullDevice }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        return (try? FileHandle(forWritingTo: url)) ?? .nullDevice
    }
}
