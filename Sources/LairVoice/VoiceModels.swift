import FluidAudio
import Foundation
import LairCore
import os

/// Speech-to-text, voice detection and the text-to-speech engine, loaded once and shared by every call.
public actor VoiceModels {
    public enum Failure: Error {
        case notLoaded
    }

    /// Where loading is: speech recognition downloads with a fraction (0...1), then the voice engine, which reports none.
    public enum Progress: Equatable, Sendable {
        case recognition(Double)
        case voices
    }

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "lair", category: "voice")

    private var asr: AsrManager?
    private var vad: VadManager?
    private nonisolated let pocket = PocketServer(model: "english_18m_2026-10", defaultVoice: Voices.defaultName())
    private nonisolated let client = PocketClient()

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

    public init() {}

    /// The folders holding the models Lair loads, and no others: FluidAudio's cache is shared with other tools.
    /// Parakeet v2 and Silero VAD sit in FluidAudio's folder in Application Support, the voices in Lair's own.
    public static var folders: [URL] {
        [
            AsrModels.defaultCacheDirectory(for: .v2),
            MLModelConfigurationUtils.defaultModelsDirectory(for: .vad),
            PocketServer.home,
        ]
    }

    /// `progress` may be called from any queue.
    public func load(warmUpVoice: String, progress: (@Sendable (Progress) -> Void)? = nil) async throws {
        let asr = AsrManager()
        progress?(.recognition(0))
        let models = try await AsrModels.downloadAndLoad(version: .v2) { progress?(.recognition($0.fractionCompleted)) }
        try await asr.loadModels(models)
        self.asr = asr
        progress?(.voices)
        // The first start downloads the voice model; the first synthesis warms it up, so pay for both now.
        _ = try await speech(for: "Ready.", voice: warmUpVoice)
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

    /// Text to 24 kHz mono samples. A voice the catalog doesn't know (an older config's) is said in the default.
    public func speech(for text: String, voice: String) async throws -> [Float] {
        let url = try await pocket.ensureRunning()
        return try await client.speech(for: text, voice: Voices.resolve(voice), at: url)
    }

    /// Stops the voice engine; called as the app quits.
    public nonisolated func stopSpeech() {
        pocket.stop()
    }
}
