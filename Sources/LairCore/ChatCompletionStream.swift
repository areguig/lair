import Foundation

/// Reads the server-sent events of a streaming `/v1/chat/completions` reply, one line at a time.
/// Hermes' `hermes.tool.progress` events report tools starting; other named events and `:` keepalives are skipped.
public struct ChatCompletionStream {
    public enum Output: Equatable, Sendable {
        case text(String)
        case toolStarted(String)
        case done
        case failed(String)
    }

    private var event: String?

    public init() {}

    // Blank lines are dropped by line readers, so an `event:` name is taken to cover the next data line only.
    public mutating func feed(_ line: String) -> Output? {
        if line.hasPrefix(":") { return nil }
        if line.hasPrefix("event:") {
            let name = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            event = name.isEmpty || name == "message" ? nil : name
            return nil
        }
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        defer { event = nil }
        if event == "hermes.tool.progress" {
            let progress = try? JSONDecoder().decode(ToolProgress.self, from: Data(payload.utf8))
            guard let progress, progress.status == "running" else { return nil }
            return .toolStarted(progress.tool)
        }
        guard event == nil else { return nil }
        if payload == "[DONE]" { return .done }
        guard let chunk = try? JSONDecoder().decode(Chunk.self, from: Data(payload.utf8)),
              let choice = chunk.choices.first
        else { return nil }
        if let reason = choice.finishReason, reason == "error" || reason == "cancelled" {
            return .failed(reason)
        }
        return choice.delta?.content.flatMap { $0.isEmpty ? nil : .text($0) }
    }

    private struct ToolProgress: Decodable {
        let tool: String
        let status: String?
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
