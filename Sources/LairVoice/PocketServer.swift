import Darwin
import Foundation
import os
import Synchronization

/// One `pocket-tts serve` process for one language model, started on first use and again if it died.
public final class PocketServer: Sendable {
    public enum Failure: Error, LocalizedError {
        case binaryMissing
        case noFreePort
        case exited(Int32)
        case timedOut

        public var errorDescription: String? {
            switch self {
            case .binaryMissing: "Lair's voice engine (pocket-tts) is missing from the app."
            case .noFreePort: "Couldn't find a free port for the voice engine."
            case .exited(let status): "The voice engine stopped (status \(status))."
            case .timedOut: "The voice engine took too long to get ready."
            }
        }
    }

    /// Where the voice models live, so they are Lair's own and Uninstall can remove them.
    public static var home: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/Lair/pocket", directoryHint: .isDirectory)
    }

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "lair", category: "voice")
    private static let binaryName = "pocket-tts"

    private struct Running {
        let process: Process
        let url: URL
    }

    private struct State {
        var running: Running?
        var starting: Task<URL, Error>?
        var stopped = false
    }

    private let model: String
    private let defaultVoice: String
    /// The first start downloads the model, so this is generous.
    private let timeout: Duration
    private let client: PocketClient
    private let state = Mutex(State())

    public init(model: String, defaultVoice: String, timeout: Duration = .seconds(600)) {
        self.model = model
        self.defaultVoice = defaultVoice
        self.timeout = timeout
        client = PocketClient()
    }

    /// Where the engine answers; starts it (and waits for the model) when it isn't running.
    public func ensureRunning() async throws -> URL {
        let task = state.withLock { state -> Task<URL, Error> in
            if let running = state.running { return Task { running.url } }
            if let starting = state.starting { return starting }
            let task = Task { try await self.launch() }
            state.starting = task
            return task
        }
        return try await task.value
    }

    /// Stops the engine, now: callable while the app quits.
    public func stop() {
        let process = state.withLock { state -> Process? in
            state.stopped = true
            defer { state.running = nil }
            return state.running?.process
        }
        process?.terminate()
    }

    // MARK: Pure parts

    /// The app's own copy, else the one `LAIR_POCKET_TTS` names (for `swift run` and tests).
    static func binary(app: URL, environment: [String: String], exists: (URL) -> Bool = { FileManager.default.isExecutableFile(atPath: $0.path) }) -> URL? {
        let bundled = app.appending(path: "Contents/Helpers/\(binaryName)")
        if exists(bundled) { return bundled }
        return environment["LAIR_POCKET_TTS"].map { URL(fileURLWithPath: $0) }.flatMap { exists($0) ? $0 : nil }
    }

    static func arguments(port: Int, model: String, defaultVoice: String) -> [String] {
        ["serve", "--host", "127.0.0.1", "--port", "\(port)", "--language", model, "--default-voice", defaultVoice]
    }

    /// A port nothing is listening on: the OS picks one when asked to bind port 0.
    static func freePort() throws -> Int {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else { throw Failure.noFreePort }
        defer { close(socket) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let size = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(socket, $0, size) } }
        var length = size
        let named = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(socket, $0, &length) } }
        guard bound == 0, named == 0 else { throw Failure.noFreePort }
        return Int(UInt16(bigEndian: address.sin_port))
    }

    // MARK: Process

    private func launch() async throws -> URL {
        defer { state.withLock { $0.starting = nil } }
        guard let binary = Self.binary(app: Bundle.main.bundleURL, environment: ProcessInfo.processInfo.environment) else {
            throw Failure.binaryMissing
        }
        let port = try Self.freePort()
        let url = URL(string: "http://127.0.0.1:\(port)")!
        let process = Process()
        process.executableURL = binary
        process.arguments = Self.arguments(port: port, model: model, defaultVoice: defaultVoice)
        process.environment = ProcessInfo.processInfo.environment.merging(["HF_HOME": Self.home.path]) { $1 }
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return handle.readabilityHandler = nil }
            Self.log.info("pocket-tts: \(String(decoding: data, as: UTF8.self), privacy: .public)")
        }
        process.terminationHandler = { [weak self] process in
            Self.log.info("pocket-tts exited with status \(process.terminationStatus)")
            self?.state.withLock { if $0.running?.process === process { $0.running = nil } }
        }
        try process.run()
        // Registered before waiting, so a quit during the model download still stops it.
        let stopped = state.withLock { state -> Bool in
            if !state.stopped { state.running = Running(process: process, url: url) }
            return state.stopped
        }
        if stopped { process.terminate(); throw CancellationError() }
        do {
            try await waitUntilHealthy(url, process: process)
        } catch {
            state.withLock { if $0.running?.process === process { $0.running = nil } }
            process.terminate()
            throw error
        }
        return url
    }

    private func waitUntilHealthy(_ url: URL, process: Process) async throws {
        let deadline = ContinuousClock.now + timeout
        while !(await client.isHealthy(at: url)) {
            if !process.isRunning { throw Failure.exited(process.terminationStatus) }
            if ContinuousClock.now > deadline { throw Failure.timedOut }
            try await Task.sleep(for: .milliseconds(250))
        }
    }
}
