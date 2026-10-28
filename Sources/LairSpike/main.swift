import AVFoundation
import FluidAudio
import Foundation
import LairCore

// Spike: push-to-talk (or a WAV file) → Parakeet → Claude Code → Kokoro, with timings.
// One Claude Code process lives for the whole call, so later turns skip its startup.
// Usage: lair-spike [--input file.wav] [--voice af_heart] [--model haiku] [--out reply.wav] [--no-play]

let args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    args.firstIndex(of: name).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
}
let voice = option("--voice") ?? "af_heart"

let clock = ContinuousClock()
func ms(_ duration: Duration) -> Int { Int(duration / .milliseconds(1)) }

print("Loading models…")
let loadStart = clock.now
let session = try ClaudeCodeSession(model: option("--model"))
let asr = AsrManager()
try await asr.loadModels(try await AsrModels.downloadAndLoad(version: .v2))
let tts = KokoroAneManager(version: .v3)
try await tts.initialize()
_ = try await tts.synthesizeDetailed(text: "Ready.", voice: voice)
print("Models ready in \(ms(clock.now - loadStart)) ms")

let speaker = try Speaker(play: !args.contains("--no-play"))

@MainActor func transcribe(_ samples: [Float]) async throws -> String {
    var decoderState = TdtDecoderState.make(decoderLayers: await asr.decoderLayerCount)
    return try await asr.transcribe(samples, decoderState: &decoderState).text
}

@MainActor func turn(_ samples: [Float]) async throws {
    let speechEnded = clock.now
    let prompt = try await transcribe(samples)
    let transcribed = clock.now
    print("You: \(prompt)")

    var splitter = SentenceSplitter()
    var firstToken: ContinuousClock.Instant?
    var firstAudio: ContinuousClock.Instant?
    func speak(_ sentence: String) async throws {
        let started = clock.now
        let audio = try await tts.synthesizeDetailed(text: sentence, voice: voice)
        print("Agent (\(ms(clock.now - started)) ms TTS for \(audio.samples.count / 24) ms audio): \(sentence)")
        speaker.enqueue(audio.samples)
        if firstAudio == nil { firstAudio = clock.now }
    }

    for await text in try session.ask(prompt) {
        if firstToken == nil { firstToken = clock.now }
        for sentence in splitter.feed(text) { try await speak(sentence) }
    }
    if let rest = splitter.flush() { try await speak(rest) }

    print("""
          transcribed \(ms(transcribed - speechEnded)) ms · first token \(firstToken.map { ms($0 - speechEnded) } ?? -1) ms \
        · first audio \(firstAudio.map { ms($0 - speechEnded) } ?? -1) ms

        """)
    await speaker.waitUntilDone()
}

if let input = option("--input") {
    let samples = try AudioConverter().resampleAudioFile(URL(fileURLWithPath: input))
    for _ in 0..<(Int(option("--turns") ?? "1") ?? 1) { try await turn(samples) }
} else {
    print("Each turn: Enter to talk, Enter when done. Press Enter twice quickly to hang up.")
    while true {
        let samples = try Recorder.recordUntilEnter()
        if samples.count < 16_000 / 2 { break }
        try await turn(samples)
    }
}
session.stop()
if let out = option("--out") { try speaker.write(to: URL(fileURLWithPath: out)) }
