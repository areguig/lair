import Foundation

/// An app opened from Finder gets a bare PATH; agents need the one your terminal has.
public enum LoginShell {
    public static func environment() async -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        if let path = await path() { environment["PATH"] = path }
        return environment
    }

    static func path() async -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        // Interactive too, as tools often add themselves to PATH only in the rc file.
        process.arguments = ["-ilc", "printf '\(marker)%s' \"$PATH\""]
        guard let result = try? await ProcessRun.run(process) else { return nil }
        return parse(result.output)
    }

    static let marker = "__LAIR_PATH__"

    /// Shell startup files may print their own text, so only what follows the marker counts.
    static func parse(_ output: String) -> String? {
        guard let range = output.range(of: marker, options: .backwards) else { return nil }
        let path = output[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }
}
