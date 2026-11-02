import AVFoundation
import LairCore

/// Plays 24 kHz mono replies back to back and meters what is heard.
@MainActor public final class Speaker {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let earconNode = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
    private let pending = DispatchGroup()
    public let meter = LevelMeter()
    private var started = PlayQueue<@MainActor () -> Void>()
    /// Changes on `stop()`, so buffers dropped by it can't move the queue on.
    private var generation = 0

    /// Which earcons play and how loud; speech is not affected.
    public var sounds = SoundSettings() {
        didSet { earconNode.volume = Float(sounds.level) }
    }

    public init() throws {
        engine.attach(node)
        engine.attach(earconNode)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.connect(earconNode, to: engine.mainMixerNode, format: format)
        // Tapping the speech node only keeps earcons off the level meter.
        node.installTap(onBus: 0, bufferSize: 1024, format: nil, block: Self.tap(meter: meter))
        try engine.start()
        node.play()
        earconNode.play()
    }

    /// `onStart` runs when this buffer begins to play, which is when the previous one has finished.
    public func enqueue(_ samples: [Float], onStart: (@MainActor () -> Void)? = nil) {
        guard !samples.isEmpty else { return }
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        pending.enter()
        let epoch = generation
        if let start = started.add(onStart ?? {}) { start() }
        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { @Sendable [pending, weak self] _ in
            pending.leave()
            Task { @MainActor in self?.bufferEnded(epoch) }
        }
    }

    private func bufferEnded(_ epoch: Int) {
        guard epoch == generation else { return }
        started.finish()?()
    }

    /// Plays on its own node: never queued with speech, never cut by `stop()`. Skipped while its group is off.
    public func play(_ earcon: Earcon) {
        guard sounds.isOn(earcon.group) else { return }
        preview(earcon)
    }

    /// Plays regardless of the switches, so Settings can let you hear what you're about to turn on.
    public func preview(_ earcon: Earcon) {
        let samples = Earcons.samples(for: earcon)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        earconNode.scheduleBuffer(buffer, at: nil, options: .interrupts)
    }

    public func waitUntilDone() async {
        await withCheckedContinuation { done in pending.notify(queue: .global()) { @Sendable in done.resume() } }
    }

    /// Drops what is queued; pending waits end as the buffers are released.
    public func stop() {
        generation += 1
        started.clear()
        node.stop()
        node.play()
        meter.set(0)
    }

    private nonisolated static func tap(meter: LevelMeter) -> AVAudioNodeTapBlock {
        { buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else { return }
            meter.set(LevelMeter.rms(Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))))
        }
    }
}
