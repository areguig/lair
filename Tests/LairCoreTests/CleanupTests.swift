import Foundation
import LairCore
import Testing

@Suite struct CleanupTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: "lair-cleanup-\(UUID().uuidString)")
    private var home: URL { root.appending(path: "home") }
    private var trashed: URL { root.appending(path: "trash") }

    private func make(_ path: String, bytes: Int = 10) throws -> URL {
        let url = home.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: bytes).write(to: url)
        return url
    }

    private final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var list: [String] = []
        func add(_ call: String) { lock.lock(); list.append(call); lock.unlock() }
        var all: [String] { lock.lock(); defer { lock.unlock() }; return list }
    }

    /// A world where the Trash is a folder in `root` and the Keychain holds `secrets`.
    private func cleanup(secrets: Set<String> = [], connected: [String] = [], calls: Calls = Calls(),
                         appFolder: URL? = nil, withApp: Bool = true) throws -> Cleanup {
        let lair = home.appending(path: ".config/lair")
        let places = Cleanup.Places(
            config: lair.appending(path: "config.json"),
            registryCache: home.appending(path: "Library/Application Support/Lair"),
            logs: home.appending(path: "Library/Logs/Lair"),
            speechModels: [home.appending(path: "Library/Application Support/Lair/pocket"),
                           home.appending(path: "Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v3"),
                           home.appending(path: "Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v2")],
            app: withApp ? (appFolder ?? home.appending(path: "Applications")).appending(path: "Lair.app") : nil)
        let trashed = trashed
        let services = Cleanup.Services(
            hasSecret: { secrets.contains("\($0)/\($1)") },
            deleteSecret: { calls.add("secret \($0)/\($1)") },
            trash: { url in
                try FileManager.default.createDirectory(at: trashed, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: url, to: trashed.appending(path: UUID().uuidString + "-" + url.lastPathComponent))
            })
        return Cleanup(
            places: places,
            connections: [("Claude Code"), ("omp")].map { name in
                Cleanup.Connection(label: name, isConnected: { connected.contains(name) },
                                   disconnect: { calls.add("disconnect \(name)") })
            },
            appItems: [Cleanup.Item(label: "Preferences", remove: { calls.add("preferences") })],
            services: services)
    }

    private func writeConfig() throws {
        let json = ##"{"agents":[{"id":"nova","name":"Nova","kind":"hermes","voice":"af_heart","color":"#fff","headers":["X-Key"]}]}"##
        let url = home.appending(path: ".config/lair/config.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: url)
    }

    @Test func resetListsSettingsSecretsAndOnlyTheConnectionsThatAreMade() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try writeConfig()
        _ = try make(".config/lair/souls/nova.md", bytes: 100)
        let secrets: Set<String> = ["lair.nova/api-key", "lair.guests/token"]
        let plan = try await cleanup(secrets: secrets, connected: ["omp"]).plan(.reset)
        #expect(plan.items.map(\.label) == ["Your agents and settings", "Saved secrets", "Connection to omp"])
        #expect(plan.notes.isEmpty)
    }

    @Test func uninstallAddsModelsCacheLogsPreferencesAndTheApp() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try make("Library/Application Support/Lair/pocket/hub/a.bin", bytes: 4000)
        _ = try make("Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v3/b.bin", bytes: 4000)
        _ = try make("Library/Application Support/Lair/registry.json")
        _ = try make("Library/Logs/Lair/nova.log")
        try FileManager.default.createDirectory(at: home.appending(path: "Applications/Lair.app"), withIntermediateDirectories: true)
        let plan = try await cleanup().plan(.uninstall)
        #expect(plan.items.map(\.label) == ["Speech models", "Cached agent list", "Logs", "Preferences", "The Lair app"])
        #expect(plan.items[0].line.contains("("))
    }

    @Test func foldersCarryTheirSizeAndItAddsUp() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try make("Library/Application Support/Lair/pocket/hub/a.bin", bytes: 100_000)
        _ = try make("Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v3/b.bin", bytes: 200_000)
        let models = try await cleanup(withApp: false).plan(.uninstall).items.first { $0.label == "Speech models" }
        #expect(models?.bytes ?? 0 >= 300_000)
        #expect(models?.bytes ?? 0 < 400_000)
    }

    @Test func theOldParakeetModelIsListedForUninstallAndLeftAloneByReset() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let old = try make("Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v2/d.bin", bytes: 4000)
        let cleanup = try cleanup(withApp: false)
        #expect(await cleanup.plan(.uninstall).items.map(\.label).contains("Speech models"))
        let reset = await cleanup.plan(.reset)
        #expect(reset.items.isEmpty)
        _ = await cleanup.run(reset)
        #expect(FileManager.default.fileExists(atPath: old.path))
    }

    @Test func missingThingsAreLeftOutWithoutComplaint() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let cleanup = try cleanup(withApp: false)
        #expect(await cleanup.plan(.reset).items.isEmpty)
        #expect(await cleanup.plan(.uninstall).items.map(\.label) == ["Preferences"])
        #expect(await cleanup.run(cleanup.plan(.uninstall)).isEmpty)
    }

    @Test func runRemovesOnlyListedItemsAndLeavesOtherToolsModelsAlone() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try writeConfig()
        let voices = try make("Library/Application Support/Lair/pocket/hub/a.bin")
        let huggingface = try make(".cache/huggingface/hub/p.bin")
        let other = try make("Library/Application Support/FluidAudio/Models/another-tool/c.bin")
        let old = try make("Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v2/d.bin")
        let mine = try make("Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v3/b.bin")
        let theirs = try make("Library/Logs/Other/x.log")
        let calls = Calls()
        let cleanup = try cleanup(secrets: ["lair.nova/header:X-Key"], connected: ["Claude Code", "omp"], calls: calls, withApp: false)
        let failures = await cleanup.run(cleanup.plan(.uninstall))
        #expect(failures.isEmpty)
        let fm = FileManager.default
        #expect(!fm.fileExists(atPath: home.appending(path: ".config/lair").path))
        #expect(!fm.fileExists(atPath: voices.path) && !fm.fileExists(atPath: mine.path) && !fm.fileExists(atPath: old.path))
        #expect(fm.fileExists(atPath: huggingface.path) && fm.fileExists(atPath: other.path) && fm.fileExists(atPath: theirs.path))
        #expect(calls.all.sorted() == ["disconnect Claude Code", "disconnect omp", "preferences", "secret lair.nova/header:X-Key"])
        #expect(fm.fileExists(atPath: trashed.path))
    }

    @Test func aFailureDoesNotStopTheRestAndIsReported() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let calls = Calls()
        struct Boom: LocalizedError { var errorDescription: String? { "no way" } }
        let plan = Cleanup.Plan(items: [
            .init(label: "First", remove: { throw Boom() }),
            .init(label: "Second", remove: { calls.add("second") }),
        ], notes: [])
        let failures = try await cleanup().run(plan)
        #expect(failures.map(\.label) == ["First"])
        #expect(failures.first?.message == "no way")
        #expect(calls.all == ["second"])
    }

    @Test func theAppStaysWhereItCannotBeRemoved() async throws {
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.appending(path: "dmg").path)
            try? FileManager.default.removeItem(at: root)
        }
        let dmg = root.appending(path: "dmg")
        try FileManager.default.createDirectory(at: dmg, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dmg.path)
        let plan = try await cleanup(appFolder: dmg).plan(.uninstall)
        #expect(!plan.items.contains { $0.label == "The Lair app" })
        #expect(plan.notes.count == 1)
    }
}
