import Foundation

/// Reads the WAV Pocket TTS streams: 16-bit mono PCM at the speaker's rate.
enum WavReader {
    enum Failure: Error, Equatable {
        case notWav
        /// What the file holds when it isn't 16-bit mono PCM at 24 kHz.
        case unsupported(String)
        case noAudio
    }

    static let sampleRate = 24_000

    /// Samples in -1...1. A streamed WAV announces a length far past its end, so the data runs to the last byte.
    static func samples(from wav: Data) throws -> [Float] {
        let bytes = [UInt8](wav)
        guard bytes.count >= 12, Array(bytes[0..<4]) == Array("RIFF".utf8), Array(bytes[8..<12]) == Array("WAVE".utf8) else {
            throw Failure.notWav
        }
        var format: (channels: Int, rate: Int, bits: Int)?
        var offset = 12
        while offset + 8 <= bytes.count {
            let id = String(decoding: bytes[offset..<offset + 4], as: UTF8.self)
            let size = Int(le32(bytes, offset + 4))
            let body = offset + 8
            switch id {
            case "fmt " where body + 16 <= bytes.count:
                format = (Int(le16(bytes, body + 2)), Int(le32(bytes, body + 4)), Int(le16(bytes, body + 14)))
            case "data":
                guard let format else { throw Failure.notWav }
                guard format.channels == 1, format.bits == 16, format.rate == sampleRate else {
                    throw Failure.unsupported("\(format.channels) channel(s), \(format.bits)-bit, \(format.rate) Hz")
                }
                let end = min(body + size, bytes.count)
                let count = (end - body) / 2
                guard count > 0 else { throw Failure.noAudio }
                return (0..<count).map { Float(Int16(bitPattern: le16(bytes, body + $0 * 2))) / 32768 }
            default:
                break
            }
            offset = body + size + size % 2
        }
        throw Failure.noAudio
    }

    private static func le16(_ bytes: [UInt8], _ at: Int) -> UInt16 {
        UInt16(bytes[at]) | UInt16(bytes[at + 1]) << 8
    }

    private static func le32(_ bytes: [UInt8], _ at: Int) -> UInt32 {
        UInt32(le16(bytes, at)) | UInt32(le16(bytes, at + 2)) << 16
    }
}
