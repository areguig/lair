import AVFoundation

/// Plays 24 kHz mono replies back to back and meters what is heard.
@MainActor public final class Speaker {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
    private let pending = DispatchGroup()
    public let meter = LevelMeter()

    public init() throws {
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil, block: Self.tap(meter: meter))
        try engine.start()
        node.play()
    }

    public func enqueue(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        pending.enter()
        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { @Sendable [pending] _ in pending.leave() }
    }

    public func waitUntilDone() async {
        await withCheckedContinuation { done in pending.notify(queue: .global()) { @Sendable in done.resume() } }
    }

    /// Drops what is queued; pending waits end as the buffers are released.
    public func stop() {
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
