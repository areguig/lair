import Foundation

/// Reads the server-sent events of a streaming `/v1/chat/completions` reply, one line at a time.
/// Named events (Hermes' `hermes.tool.progress`) and `:` keepalives are skipped.
public struct ChatCompletionStream {
    public enum Output: Equatable, Sendable {
        case text(String)
        case done
        case failed(String)
    }

    private var namedEvent = false

    public init() {}

    // Blank lines are dropped by line readers, so an `event:` name is taken to cover the next data line only.
    public mutating func feed(_ line: String) -> Output? {
        if line.hasPrefix(":") { return nil }
        if line.hasPrefix("event:") {
            let name = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            namedEvent = !name.isEmpty && name != "message"
            return nil
        }
        guard line.hasPrefix("data:") else { return nil }
        defer { namedEvent = false }
        guard !namedEvent else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return .done }
        guard let chunk = try? JSONDecoder().decode(Chunk.self, from: Data(payload.utf8)),
              let choice = chunk.choices.first
        else { return nil }
        if let reason = choice.finishReason, reason == "error" || reason == "cancelled" {
            return .failed(reason)
        }
        return choice.delta?.content.flatMap { $0.isEmpty ? nil : .text($0) }
    }

    private struct Chunk: Decodable {
        let choices: [Choice]
    }

    private struct Choice: Decodable {
        let delta: Delta?
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    private struct Delta: Decodable {
        let content: String?
    }
}
