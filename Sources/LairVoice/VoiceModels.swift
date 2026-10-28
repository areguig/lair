import FluidAudio
import Foundation

/// Speech-to-text and text-to-speech models, loaded once and shared by every call.
public actor VoiceModels {
    public enum Failure: Error {
        case notLoaded
    }

    private var asr: AsrManager?
    private var tts: KokoroAneManager?

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
