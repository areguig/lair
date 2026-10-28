import AVFoundation
import FluidAudio
import Synchronization

/// Push-to-talk capture. The engine runs for the whole call so the first word isn't clipped by its startup.
@MainActor public final class Microphone {
    private var engine: AVAudioEngine?
    private var sampleRate: Double = 0
    private let capture = Capture()
    public let meter = LevelMeter()

    public init() {}

    public static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    public func open() throws {
        guard engine == nil else { return }
        let engine = AVAudioEngine()
        let format = engine.inputNode.outputFormat(forBus: 0)
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format,
                                    block: Self.tap(capture: capture, meter: meter))
        try engine.start()
        self.engine = engine
        sampleRate = format.sampleRate
    }

    public func close() {
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        capture.stop()
        meter.set(0)
    }

    public func startCapture() {
        capture.start()
    }

    /// The audio since `startCapture`, as 16 kHz mono.
    public func stopCapture() throws -> [Float] {
        let raw = capture.stop()
        meter.set(0)
        guard !raw.isEmpty, sampleRate > 0 else { return [] }
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(raw.count))!
        buffer.frameLength = AVAudioFrameCount(raw.count)
        raw.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: raw.count) }
        return try AudioConverter().resampleBuffer(buffer)
    }

    // Built outside the main actor: the tap runs on the audio thread.
    private nonisolated static func tap(capture: Capture, meter: LevelMeter) -> AVAudioNodeTapBlock {
        { buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else { return }
            let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            if capture.append(samples) { meter.set(LevelMeter.rms(samples)) }
        }
    }

    private final class Capture: Sendable {
        private let state = Mutex<(recording: Bool, samples: [Float])>((false, []))

        func start() { state.withLock { $0 = (true, []) } }

        @discardableResult
        func stop() -> [Float] { state.withLock { state in defer { state = (false, []) }; return state.samples } }

        /// Returns whether the samples were kept.
        func append(_ samples: [Float]) -> Bool {
            state.withLock { state in
                guard state.recording else { return false }
                state.samples += samples
                return true
            }
        }
    }
}
