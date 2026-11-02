import Foundation
import LairCore
import Observation
import os

/// The ACP Registry as last fetched: kept on disk, so it's there offline, and refreshed with a conditional GET.
@Observable @MainActor final class RegistryStore {
    private(set) var registry: Registry?
    private(set) var isLoading = false
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let session: URLSession

    static let indexURL = URL(string: "https://cdn.agentclientprotocol.com/registry/v1/latest/registry.json")!
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "lair", category: "registry")

    init(directory: URL = URL.applicationSupportDirectory.appending(path: "Lair"), session: URLSession = .shared) {
        self.directory = directory
        self.session = session
        if let data = try? Data(contentsOf: indexFile) { registry = try? JSONDecoder().decode(Registry.self, from: data) }
    }

    /// A store that already holds `registry`, for snapshots.
    init(registry: Registry) {
        self.registry = registry
        directory = FileManager.default.temporaryDirectory
        session = .shared
    }

    private var indexFile: URL { directory.appending(path: "registry.json") }
    private var etagFile: URL { directory.appending(path: "registry.etag") }

    /// Asks the CDN for a newer index; whatever it already has stays when offline or when the answer is unusable.
    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        var request = URLRequest(url: Self.indexURL, cachePolicy: .reloadIgnoringLocalCacheData)
        if registry != nil, let etag = try? String(contentsOf: etagFile, encoding: .utf8) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode != 304 else { return }
            guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
            registry = try JSONDecoder().decode(Registry.self, from: data)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: indexFile, options: .atomic)
            try http.value(forHTTPHeaderField: "ETag")?.write(to: etagFile, atomically: true, encoding: .utf8)
        } catch {
            Self.log.error("refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
