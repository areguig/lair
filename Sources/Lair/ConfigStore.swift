import Foundation
import LairCore
import Observation
import os

/// The config file is the source of truth: the settings window writes it, and edits made by hand are picked up.
@Observable @MainActor final class ConfigStore {
    private(set) var config: LairConfig
    private(set) var problem: String?
    @ObservationIgnored var onChange: ((LairConfig) -> Void)?
    @ObservationIgnored private let url: URL
    @ObservationIgnored private var modified: Date?
    @ObservationIgnored private var watcher: Timer?

    /// How often the file is checked for edits made outside Lair.
    private static let checkEvery: TimeInterval = 2
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "lair", category: "config")

    init(url: URL = LairConfig.defaultURL) {
        self.url = url
        do {
            config = try LairConfig.load(from: url)
        } catch {
            config = .initial
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
            guard loaded != config else { return }
            config = loaded
            onChange?(loaded)
        } catch {
            // Keep running with the last good config until the file is fixed.
            problem = "The config file has an error: \(error.localizedDescription)"
        }
    }

    private static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}
