import Foundation
import os

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

    /// Starts, stops and stray output of agent processes: `log show --predicate 'category == "agent"'`.
    static let events = Logger(subsystem: Bundle.main.bundleIdentifier ?? "lair", category: "agent")

    /// Starts the agent and notes when it exits, so a call that dies quietly leaves a trace.
    public static func run(_ process: Process) throws {
        let name = process.arguments?.first ?? "agent"
        process.terminationHandler = { process in
            let how = process.terminationReason == .uncaughtSignal ? "signal" : "status"
            events.notice("\(name, privacy: .public) \(process.processIdentifier) exited, \(how, privacy: .public) \(process.terminationStatus)")
        }
        try process.run()
        events.notice("\(name, privacy: .public) \(process.processIdentifier) started in \(process.currentDirectoryURL?.path ?? "~", privacy: .public)")
    }

    /// A line on stdout that isn't the JSON protocol, such as a sign-in or crash message.
    public static func stray(_ line: String) {
        guard !line.hasPrefix("{"), !line.isEmpty else { return }
        events.notice("stray output: \(line, privacy: .public)")
    }

    public static func handle(for url: URL?) -> FileHandle {
        guard let url else { return .nullDevice }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        return (try? FileHandle(forWritingTo: url)) ?? .nullDevice
    }
}

/// The agent's process has exited; whatever it printed is in its log.
public struct AgentStopped: Error {
    public init() {}
}
