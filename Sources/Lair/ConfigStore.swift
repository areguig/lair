import Foundation
import LairCore
import Observation
import os

/// The config file is the source of truth: the settings window writes it, and edits made by hand are picked up.
@Observable @MainActor final class ConfigStore {
    private(set) var config: LairConfig
    private(set) var problem: String?
    /// There was no config file when Lair started: this is the first launch.
    let isNew: Bool
    @ObservationIgnored var onChange: ((LairConfig) -> Void)?
    @ObservationIgnored private let url: URL
    @ObservationIgnored private var modified: Date?
    @ObservationIgnored private var watcher: Timer?
    /// The file on disk couldn't be read; it's kept aside before Lair writes over it.
    @ObservationIgnored private var unreadable = false

    /// How often the file is checked for edits made outside Lair.
    private static let checkEvery: TimeInterval = 2
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "lair", category: "config")

    init(url: URL = LairConfig.defaultURL) {
        self.url = url
        isNew = !LairConfig.exists(at: url)
        do {
            config = try LairConfig.load(from: url)
        } catch {
            config = .initial
            unreadable = true
            problem = "Couldn't read the config file: \(error.localizedDescription)"
        }
        modified = Self.modificationDate(of: url)
    }

    func watch() {
        watcher = Timer.scheduledTimer(withTimeInterval: Self.checkEvery, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadIfEdited() }
        }
    }

    func save(_ new: LairConfig) {
        guard new != config else { return }
        do {
            if unreadable {
                let backup = url.deletingPathExtension().appendingPathExtension("broken.json")
                try? FileManager.default.removeItem(at: backup)
                try FileManager.default.copyItem(at: url, to: backup)
                unreadable = false
            }
            try new.save(to: url)
            config = new
            problem = nil
            modified = Self.modificationDate(of: url)
            onChange?(new)
        } catch {
            problem = "Couldn't save the config file: \(error.localizedDescription)"
            Self.log.error("save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func reloadIfEdited() {
        let date = Self.modificationDate(of: url)
        guard date != modified else { return }
        modified = date
        do {
            let loaded = try LairConfig.load(from: url)
            problem = nil
            unreadable = false
            guard loaded != config else { return }
            config = loaded
            onChange?(loaded)
        } catch {
            // Keep running with the last good config until the file is fixed.
            unreadable = true
            problem = "The config file has an error: \(error.localizedDescription)"
        }
    }

    private static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}
