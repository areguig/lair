import Foundation
import Security

/// Registers Lair in the config of each coding agent that can join it, under one server name.
public enum GuestConnection {
    /// The same name everywhere, so omp, which also reads Claude Code's servers, keeps only one.
    public static let serverName = "lair"

    /// The bearer token agents send, made once and kept in the Keychain.
    public static func token() throws -> String {
        let service = GuestSettings.keychainService, account = GuestSettings.keychainAccount
        if let token = Keychain.password(service: service, account: account) { return token }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw Failure.noRandom }
        let token = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        try Keychain.setPassword(token, service: service, account: account)
        return token
    }

    public enum Failure: LocalizedError {
        case noRandom
        case command(String)

        public var errorDescription: String? {
            switch self {
            case .noRandom: "Couldn't make a token."
            case .command(let output): output
            }
        }
    }

    /// omp: its user `mcp.json`, edited in place, keeping every other server.
    public struct Omp: Sendable {
        public let file: URL

        public static let standard = Omp(file: FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".omp/agent/mcp.json"))

        public init(file: URL) {
            self.file = file
        }

        public var isConnected: Bool { (try? servers())?[serverName] != nil }

        /// omp gives up on a tool call after 30 s unless told otherwise, so its timeout covers the answer wait.
        public func connect(url: URL, token: String, answerSeconds: Int) throws {
            var all = try servers()
            all[serverName] = [
                "type": "http",
                "url": url.absoluteString,
                "headers": ["Authorization": "Bearer \(token)"],
                "timeout": (answerSeconds + 30) * 1000,
            ]
            try write(all)
        }

        public func disconnect() throws {
            var all = try servers()
            guard all.removeValue(forKey: serverName) != nil else { return }
            try write(all)
        }

        private func document() throws -> [String: Any] {
            guard FileManager.default.fileExists(atPath: file.path) else { return [:] }
            return try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any] ?? [:]
        }

        private func servers() throws -> [String: Any] {
            try document()["mcpServers"] as? [String: Any] ?? [:]
        }

        private func write(_ servers: [String: Any]) throws {
            var document = try document()
            document["mcpServers"] = servers
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: document,
                                                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try data.write(to: file, options: .atomic)
        }
    }

    /// Claude Code: through its own CLI, at user scope, so every session on this Mac can join.
    public struct ClaudeCode: Sendable {
        /// The CLI, found on the login shell's PATH.
        public let command: String
        public let environment: [String: String]

        public init(command: String = "claude", environment: [String: String]) {
            self.command = command
            self.environment = environment
        }

        public func isConnected() async -> Bool {
            (try? await run(["mcp", "get", serverName])) != nil
        }

        public func connect(url: URL, token: String) async throws {
            if await isConnected() { try await disconnect() }
            try await run(["mcp", "add", "--scope", "user", "--transport", "http", serverName, url.absoluteString,
                           "--header", "Authorization: Bearer \(token)"])
        }

        public func disconnect() async throws {
            try await run(["mcp", "remove", "--scope", "user", serverName])
        }

        @discardableResult
        private func run(_ arguments: [String]) async throws -> String {
            try await GuestConnection.run(command, arguments, environment: environment)
        }
    }

    /// Whether `command` runs at all on the login shell's PATH.
    public static func isInstalled(_ command: String, environment: [String: String]) async -> Bool {
        (try? await run(command, ["--version"], environment: environment)) != nil
    }

    /// Its output, or what it said when it failed.
    @discardableResult
    static func run(_ command: String, _ arguments: [String], environment: [String: String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments
        process.environment = environment
        let result = try await ProcessRun.run(process, includingErrors: true)
        guard result.status == 0 else { throw Failure.command(result.output.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return result.output
    }
}
