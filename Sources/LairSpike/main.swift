import AVFoundation
import FluidAudio
import Foundation
import LairCore

// Spike: push-to-talk (or a WAV file) → Parakeet → Claude Code → Kokoro, with timings.
// Usage: lair-spike [--input file.wav] [--voice af_heart] [--model haiku] [--out reply.wav] [--no-play]

let args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    args.firstIndex(of: name).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
}
let voice = option("--voice") ?? "af_heart"
let play = !args.contains("--no-play")

let clock = ContinuousClock()
func ms(_ duration: Duration) -> Int { Int(duration / .milliseconds(1)) }

print("Loading models…")
var loadStart = clock.now
let asr = AsrManager()
try await asr.loadModels(try await AsrModels.downloadAndLoad(version: .v2))
let tts = KokoroAneManager(version: .v3)
try await tts.initialize()
_ = try await tts.synthesizeDetailed(text: "Ready.", voice: voice)
print("Models ready in \(ms(clock.now - loadStart)) ms")

let samples: [Float]
if let input = option("--input") {
    samples = try AudioConverter().resampleAudioFile(URL(fileURLWithPath: input))
} else {
    samples = try Recorder.recordUntilEnter()
}
let speechEnded = clock.now

@MainActor func transcribe(_ samples: [Float]) async throws -> String {
    var decoderState = TdtDecoderState.make(decoderLayers: await asr.decoderLayerCount)
    return try await asr.transcribe(samples, decoderState: &decoderState).text
}
let prompt = try await transcribe(samples)
let transcribed = clock.now
print("You: \(prompt)")

let claude = Process()
claude.executableURL = URL(fileURLWithPath: "/usr/bin/env")
claude.arguments = ["claude", "-p", prompt, "--output-format", "stream-json", "--verbose",
                    "--include-partial-messages", "--no-session-persistence",
                    "--append-system-prompt", VoicePrompt.text]
    + (option("--model").map { ["--model", $0] } ?? [])
let stdout = Pipe()
claude.standardOutput = stdout
claude.standardError = FileHandle.nullDevice
try claude.run()

let speaker = try Speaker(play: play)
var splitter = SentenceSplitter()
var firstToken: ContinuousClock.Instant?
var firstAudio: ContinuousClock.Instant?

@MainActor func speak(_ sentence: String) async throws {
    let started = clock.now
    let audio = try await tts.synthesizeDetailed(text: sentence, voice: voice)
    print("Agent (\(ms(clock.now - started)) ms TTS for \(audio.samples.count / 24) ms audio): \(sentence)")
    speaker.enqueue(audio.samples)
    if firstAudio == nil { firstAudio = clock.now }
}

for try await line in stdout.fileHandleForReading.bytes.lines {
    guard case .textDelta(let text) = ClaudeCodeStream.parse(line: line) else { continue }
    if firstToken == nil { firstToken = clock.now }
    for sentence in splitter.feed(text) { try await speak(sentence) }
}
if let rest = splitter.flush() { try await speak(rest) }
claude.waitUntilExit()

print("""

    Timings from end of speech:
      transcribed   \(ms(transcribed - speechEnded)) ms (\(samples.count / 16) ms of audio)
      first token   \(firstToken.map { ms($0 - speechEnded) } ?? -1) ms
      first audio   \(firstAudio.map { ms($0 - speechEnded) } ?? -1) ms
    """)

await speaker.waitUntilDone()
if let out = option("--out") { try speaker.write(to: URL(fileURLWithPath: out)) }
