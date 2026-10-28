import Synchronization

/// Loudness from 0 to 1, written by the audio thread and read by the orb on each frame.
public final class LevelMeter: Sendable {
    private let value = Mutex<Float>(0)

    public init() {}

    public var level: Float { value.withLock { $0 } }

    public func set(_ level: Float) { value.withLock { $0 = level } }

    /// Speech RMS sits around 0.02–0.2, so it is scaled up and capped to fill the 0–1 range.
    public static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let mean = samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)
        return min(1, mean.squareRoot() * 6)
    }
}
