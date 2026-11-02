import Foundation
@testable import LairVoice
import Testing

struct WavReaderTests {
    /// A WAV as Pocket writes it: a 44-byte header, then 16-bit mono PCM.
    static func wav(_ samples: [Int16], rate: UInt32 = 24_000, channels: UInt16 = 1, announced: UInt32? = nil) -> Data {
        func le<T: FixedWidthInteger>(_ value: T) -> [UInt8] { withUnsafeBytes(of: value.littleEndian) { Array($0) } }
        let size = announced ?? UInt32(samples.count * 2)
        var bytes = Array("RIFF".utf8) + le(36 + size) + Array("WAVEfmt ".utf8) + le(UInt32(16)) + le(UInt16(1)) + le(channels)
        bytes += le(rate) + le(rate * 2) + le(UInt16(2)) + le(UInt16(16)) + Array("data".utf8) + le(size)
        return Data(bytes + samples.flatMap { le($0) })
    }

    @Test func readsSamplesAsFloats() throws {
        let samples = try WavReader.samples(from: Self.wav([0, 16384, -16384, -32768]))
        #expect(samples == [0, 0.5, -0.5, -1])
    }

    @Test func aStreamedWavAnnouncingMoreThanItHoldsRunsToItsEnd() throws {
        let samples = try WavReader.samples(from: Self.wav([100, 200, 300], announced: 2_000_000_000))
        #expect(samples.count == 3)
    }

    @Test func skipsChunksItDoesNotKnow() throws {
        var wav = Self.wav([1000])
        let header = wav.prefix(36)
        let extra = Data(Array("LIST".utf8) + [2, 0, 0, 0, 0xAA, 0xBB])
        wav = header + extra + wav.dropFirst(36)
        #expect(try WavReader.samples(from: wav).count == 1)
    }

    @Test func refusesWhatItCouldNotPlayAtTheRightSpeed() {
        #expect(throws: WavReader.Failure.unsupported("1 channel(s), 16-bit, 16000 Hz")) {
            try WavReader.samples(from: Self.wav([1, 2], rate: 16_000))
        }
        #expect(throws: WavReader.Failure.unsupported("2 channel(s), 16-bit, 24000 Hz")) {
            try WavReader.samples(from: Self.wav([1, 2], channels: 2))
        }
    }

    @Test func refusesNonWavAndEmptyAudio() {
        #expect(throws: WavReader.Failure.notWav) { try WavReader.samples(from: Data("{}".utf8)) }
        #expect(throws: WavReader.Failure.noAudio) { try WavReader.samples(from: Self.wav([])) }
    }
}
