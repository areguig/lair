import Foundation

/// Cuts streamed text into sentences so TTS can start before the agent finishes.
public struct SentenceSplitter {
    private var buffer = ""

    public init() {}

    public mutating func feed(_ text: String) -> [String] {
        buffer += text
        var sentences: [String] = []
        while let end = firstBoundary() {
            let sentence = buffer[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
            buffer = String(buffer[end...])
            if !sentence.isEmpty { sentences.append(sentence) }
        }
        return sentences
    }

    public mutating func flush() -> String? {
        let rest = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        return rest.isEmpty ? nil : rest
    }

    // A boundary needs the following character, so "3.5" and a trailing "." still waiting for more text are not cut.
    private func firstBoundary() -> String.Index? {
        var index = buffer.startIndex
        while index < buffer.endIndex {
            let next = buffer.index(after: index)
            if buffer[index] == "\n" { return next }
            if ".!?".contains(buffer[index]), next < buffer.endIndex, buffer[next].isWhitespace { return next }
            index = next
        }
        return nil
    }
}
