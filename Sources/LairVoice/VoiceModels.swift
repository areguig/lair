import FluidAudio
import Foundation
import os

/// Speech-to-text and text-to-speech models, loaded once and shared by every call.
public actor VoiceModels {
    public enum Failure: Error {
        case notLoaded
    }

    /// Where loading is: speech recognition downloads with a fraction (0...1), then the voices, which report none.
    public enum Progress: Equatable, Sendable {
        case recognition(Double)
        case voices
    }

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "lair", category: "voice")

    private var asr: AsrManager?
    private var tts: KokoroAneManager?
    private var vad: VadManager?

    /// Where the voice detector is in what it has heard so far.
    public struct Detector: Sendable {
        fileprivate var state: VadStreamState
        /// 16 kHz samples already heard.
        public fileprivate(set) var heard = 0
        public var speaking: Bool { state.triggered }
    }

    /// The detector reads 16 kHz audio in chunks of this many samples (256 ms).
    public static let detectorChunk = VadManager.chunkSize
    /// Silence that ends speech; short, so your answer goes as soon as you stop.
    private static let endOfSpeech = VadSegmentationConfig(minSilenceDuration: 0.8)

    /// Kokoro's English voices: American (`a`) and British (`b`), female (`f`) and male (`m`).
    public static let voices = KokoroAneConstants.englishVoices.filter { $0.hasPrefix("a") || $0.hasPrefix("b") }

    public init() {}

    /// The Kokoro chain for an OS: v3 hard-codes its noise and source-generator stages to the GPU, which aborts in
    /// MPSGraph on macOS 27 (FluidAudio #843); the legacy chain follows `KokoroAneComputeUnits.default`, which has no GPU stage there.
    public static func kokoroVersion(for os: OperatingSystemVersion) -> KokoroAneVersion {
        os.majorVersion >= 27 ? .legacy : .v3
    }

    /// The folders holding the models Lair loads, and no others: FluidAudio's cache is shared with other tools.
    /// Parakeet v2 and Silero VAD sit in Application Support, the Kokoro chain this OS loads in `~/.cache`.
    /// Kokoro's G2P folder stays: every Kokoro backend shares it, with other languages' lexicons.
    public static var folders: [URL] { folders(for: ProcessInfo.processInfo.operatingSystemVersion) }

    static func folders(for os: OperatingSystemVersion) -> [URL] {
        let tts = ttsCache.appending(path: "Models", directoryHint: .isDirectory)
        let kokoro: String
        switch kokoroVersion(for: os) {
        // KokoroAneV3Assets.swift:71, whatever its revision or language.
        case .v3: kokoro = "kokoro-82m-coreml/ANE-v3"
        // KokoroAneResourceDownloader.swift:22, the English variant.
        case .legacy: kokoro = Repo.kokoroAne.folderName
        }
        return [
            AsrModels.defaultCacheDirectory(for: .v2),
            MLModelConfigurationUtils.defaultModelsDirectory(for: .vad),
            tts.appending(path: kokoro, directoryHint: .isDirectory),
        ]
    }

    /// FluidAudio's text-to-speech root on macOS, which it builds in TtsCacheDirectory.swift:25-38.
    private static var ttsCache: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".cache/fluidaudio", directoryHint: .isDirectory)
    }

    /// `progress` may be called from any queue.
    public func load(warmUpVoice: String, progress: (@Sendable (Progress) -> Void)? = nil) async throws {
        let asr = AsrManager()
        progress?(.recognition(0))
        let models = try await AsrModels.downloadAndLoad(version: .v2) { progress?(.recognition($0.fractionCompleted)) }
        try await asr.loadModels(models)
        progress?(.voices)
        let version = Self.kokoroVersion(for: ProcessInfo.processInfo.operatingSystemVersion)
        // A tester's log shows which chain ran; the legacy chain's default routing keeps the GPU out on macOS 27.
        Self.log.info("Kokoro chain: \(version.rawValue, privacy: .public)")
        let tts = KokoroAneManager(version: version)
        try await tts.initialize()
        // The first synthesis compiles the models; pay for it now rather than on the first reply.
        _ = try await tts.synthesizeDetailed(text: "Ready.", voice: warmUpVoice)
        self.asr = asr
        self.tts = tts
        // Only listening for answers needs it; without it you press the key as before.
        vad = try? await VadManager()
    }

    /// A fresh detector, or nil when the model couldn't load.
    public func detector() -> Detector? {
        vad == nil ? nil : Detector(state: .initial())
    }

    /// Feeds the detector every whole chunk of `samples` it hasn't heard yet.
    public func listen(_ detector: Detector, to samples: [Float]) async throws -> Detector {
        guard let vad else { throw Failure.notLoaded }
        var detector = detector
        while samples.count - detector.heard >= Self.detectorChunk {
            let chunk = Array(samples[detector.heard..<detector.heard + Self.detectorChunk])
            detector.state = try await vad.processStreamingChunk(chunk, state: detector.state, config: Self.endOfSpeech).state
            detector.heard += Self.detectorChunk
        }
        return detector
    }

    /// 16 kHz mono samples to text.
    public func transcribe(_ samples: [Float]) async throws -> String {
        guard let asr else { throw Failure.notLoaded }
        var decoderState = TdtDecoderState.make(decoderLayers: await asr.decoderLayerCount)
        return try await asr.transcribe(samples, decoderState: &decoderState).text
    }

    /// Text to 24 kHz mono samples.
    public func speech(for text: String, voice: String) async throws -> [Float] {
        guard let tts else { throw Failure.notLoaded }
        return try await tts.synthesizeDetailed(text: text, voice: voice).samples
    }
}
