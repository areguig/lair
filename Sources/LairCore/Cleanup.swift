import Foundation

/// What Reset and Uninstall remove: only what Lair made, listed so you can see it before anything goes.
/// Files move to the Trash, so they can be put back; Keychain items and connections are removed for good.
public struct Cleanup: Sendable {
    public enum Scope: Sendable { case reset, uninstall }

    /// One line of the list: what it is, how big when it is a folder, and how to remove it.
    public struct Item: Sendable {
        public let label: String
        public let bytes: Int64?
        let remove: @Sendable () async throws -> Void

        public init(label: String, bytes: Int64? = nil, remove: @escaping @Sendable () async throws -> Void) {
            self.label = label
            self.bytes = bytes
            self.remove = remove
        }

        /// The label with its size, as the confirmation shows it.
        public var line: String {
            bytes.map { "\(label) (\(ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)))" } ?? label
        }
    }

    /// A coding agent Lair was added to; only offered while it is connected.
    public struct Connection: Sendable {
        public let label: String
        public let isConnected: @Sendable () async -> Bool
        public let disconnect: @Sendable () async throws -> Void

        public init(label: String, isConnected: @escaping @Sendable () async -> Bool,
                    disconnect: @escaping @Sendable () async throws -> Void) {
            self.label = label
            self.isConnected = isConnected
            self.disconnect = disconnect
        }
    }

    /// Where Lair keeps things; tests point these at temporary folders.
    public struct Places: Sendable {
        public var config: URL
        public var configFolder: URL
        /// The agent list cached from the ACP Registry.
        public var registryCache: URL
        public var logs: URL
        /// The speech model folders, and only those: other tools keep their own models beside them.
        public var speechModels: [URL]
        /// The app itself, when it is to be removed.
        public var app: URL?

        public init(config: URL, registryCache: URL, logs: URL, speechModels: [URL], app: URL?) {
            self.config = config
            configFolder = config.deletingLastPathComponent()
            self.registryCache = registryCache
            self.logs = logs
            self.speechModels = speechModels
            self.app = app
        }

        public static func standard(speechModels: [URL], app: URL?) -> Places {
            let home = FileManager.default.homeDirectoryForCurrentUser
            return Places(config: LairConfig.defaultURL,
                          registryCache: home.appending(path: "Library/Application Support/Lair"),
                          logs: home.appending(path: "Library/Logs/Lair"),
                          speechModels: speechModels, app: app)
        }
    }

    /// The Keychain and the Trash, replaceable so tests touch neither.
    public struct Services: Sendable {
        public var hasSecret: @Sendable (_ service: String, _ account: String) -> Bool
        public var deleteSecret: @Sendable (_ service: String, _ account: String) -> Void
        public var trash: @Sendable (URL) throws -> Void

        public init(hasSecret: @escaping @Sendable (String, String) -> Bool,
                    deleteSecret: @escaping @Sendable (String, String) -> Void,
                    trash: @escaping @Sendable (URL) throws -> Void) {
            self.hasSecret = hasSecret
            self.deleteSecret = deleteSecret
            self.trash = trash
        }

        public static let system = Services(
            hasSecret: { Keychain.password(service: $0, account: $1) != nil },
            deleteSecret: { Keychain.delete(service: $0, account: $1) },
            trash: { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) })
    }

    public struct Plan: Sendable {
        public var items: [Item]
        /// Things that will stay, and why.
        public var notes: [String]

        public init(items: [Item], notes: [String] = []) {
            self.items = items
            self.notes = notes
        }
    }

    public struct Failure: Sendable {
        public let label: String
        public let message: String
    }

    public let places: Places
    public let connections: [Connection]
    public let services: Services
    /// Uninstall only: the login item and preferences, which live in the app rather than in files.
    public let appItems: [Item]

    public init(places: Places, connections: [Connection], appItems: [Item] = [], services: Services = .system) {
        self.places = places
        self.connections = connections
        self.appItems = appItems
        self.services = services
    }

    /// What `scope` would remove right now; whatever isn't there is left out.
    public func plan(_ scope: Scope) async -> Plan {
        var items: [Item] = []
        if let item = folder("Your agents and settings", places.configFolder) { items.append(item) }
        if let item = secrets() { items.append(item) }
        for connection in connections where await connection.isConnected() {
            items.append(Item(label: "Connection to \(connection.label)", remove: connection.disconnect))
        }
        guard scope == .uninstall else { return Plan(items: items) }
        let models = places.speechModels.filter(exists)
        if !models.isEmpty {
            let trash = services.trash
            items.append(Item(label: "Speech models", bytes: models.reduce(0) { $0 + Self.size(of: $1) },
                              remove: { for model in models { try trash(model) } }))
        }
        items += [folder("Cached agent list", places.registryCache), folder("Logs", places.logs)].compactMap { $0 }
        items += appItems
        var notes: [String] = []
        if let app = places.app {
            if Self.canRemove(app) {
                let trash = services.trash
                items.append(Item(label: "The Lair app", remove: { try trash(app) }))
            } else {
                notes.append("Lair is not in a place it can be removed from (a disk image, say), so the app stays.")
            }
        }
        return Plan(items: items, notes: notes)
    }

    /// Removes the items in order, going on past one that fails; what failed comes back.
    public func run(_ plan: Plan) async -> [Failure] {
        var failures: [Failure] = []
        for item in plan.items {
            do { try await item.remove() } catch { failures.append(Failure(label: item.label, message: error.localizedDescription)) }
        }
        return failures
    }

    /// The Keychain items of every agent in the config and of the MCP token, those that exist.
    private func secrets() -> Item? {
        // Read directly: `LairConfig.load` would write a new config file where there is none.
        let agents = (try? JSONDecoder().decode(LairConfig.self, from: Data(contentsOf: places.config)))?.agents ?? []
        let all = agents.flatMap { agent in agent.secretAccounts.map { (agent.keychainService, $0) } }
            + [(GuestSettings.keychainService, GuestSettings.keychainAccount)]
        let found = all.filter { services.hasSecret($0.0, $0.1) }
        guard !found.isEmpty else { return nil }
        let delete = services.deleteSecret
        return Item(label: "Saved secrets", remove: { for (service, account) in found { delete(service, account) } })
    }

    private func folder(_ label: String, _ url: URL) -> Item? {
        guard exists(url) else { return nil }
        let trash = services.trash
        return Item(label: label, bytes: Self.size(of: url), remove: { try trash(url) })
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    /// Whether the app can be moved out of the folder it is in.
    static func canRemove(_ app: URL) -> Bool {
        FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path)
    }

    /// Bytes on disk of a file or everything inside a folder.
    static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else { return 0 }
        return files.compactMap { $0 as? URL }.reduce(into: 0) { total, file in
            let values = try? file.resourceValues(forKeys: keys)
            if values?.isRegularFile == true { total += Int64(values?.totalFileAllocatedSize ?? 0) }
        }
    }
}
