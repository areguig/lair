import FluidAudio
import Foundation

/// Speech-to-text and text-to-speech models, loaded once and shared by every call.
public actor VoiceModels {
    public enum Failure: Error {
        case notLoaded
    }

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

    public func load(warmUpVoice: String) async throws {
        let asr = AsrManager()
        try await asr.loadModels(try await AsrModels.downloadAndLoad(version: .v2))
        let tts = KokoroAneManager(version: .v3)
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
