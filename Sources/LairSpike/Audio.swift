import AVFoundation
import FluidAudio
import Foundation

/// Records the default microphone between two presses of Enter.
enum Recorder {
    static func recordUntilEnter() throws -> [Float] {
        let engine = AVAudioEngine()
        let format = engine.inputNode.outputFormat(forBus: 0)
        let collected = Collected()
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else { return }
            collected.append(Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))))
        }
        print("Press Enter to talk…", terminator: "")
        _ = readLine()
        try engine.start()
        print("Listening. Press Enter when done.", terminator: "")
        _ = readLine()
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)

        let raw = collected.samples
        let mono = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: AVAudioFrameCount(raw.count))!
        buffer.frameLength = AVAudioFrameCount(raw.count)
        raw.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: raw.count) }
        return try AudioConverter().resampleBuffer(buffer)
    }

    private final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [Float] = []
        func append(_ chunk: [Float]) { lock.withLock { storage += chunk } }
        var samples: [Float] { lock.withLock { storage } }
    }
}

/// Plays 24 kHz mono chunks back to back and keeps a copy for `--out`.
final class Speaker {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
    private let pending = DispatchGroup()
    private let play: Bool
    private var recorded: [Float] = []

    init(play: Bool) throws {
        self.play = play
        guard play else { return }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        try engine.start()
        node.play()
    }

    func enqueue(_ samples: [Float]) {
        recorded += samples
        guard play, !samples.isEmpty else { return }
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        pending.enter()
        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [pending] _ in pending.leave() }
    }

    func waitUntilDone() async {
        await withCheckedContinuation { done in pending.notify(queue: .global()) { done.resume() } }
    }

    func write(to url: URL) throws {
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(recorded.count))!
        buffer.frameLength = AVAudioFrameCount(recorded.count)
        recorded.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: recorded.count) }
        try file.write(from: buffer)
    }
}
