import LairVoice
import Testing

struct LevelMeterTests {
    @Test func silenceIsZeroAndLoudnessIsCapped() {
        #expect(LevelMeter.rms([]) == 0)
        #expect(LevelMeter.rms([0, 0, 0]) == 0)
        #expect(LevelMeter.rms([1, -1, 1]) == 1)
    }

    @Test func typicalSpeechLandsMidRange() {
        let level = LevelMeter.rms(Array(repeating: 0.08, count: 100))
        #expect(level > 0.3 && level < 0.7)
    }
}
