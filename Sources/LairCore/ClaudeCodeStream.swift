import Foundation

public enum AgentEvent: Equatable, Sendable {
    case textDelta(String)
    case finished(String)
}

/// Reads one line of `claude -p --output-format stream-json --include-partial-messages`.
public enum ClaudeCodeStream {
    public static func parse(line: String) -> AgentEvent? {
        guard let data = line.data(using: .utf8),
              let message = try? JSONDecoder().decode(Message.self, from: data)
        else { return nil }
        switch message.type {
        case "stream_event" where message.event?.delta?.type == "text_delta":
            return message.event?.delta?.text.map(AgentEvent.textDelta)
        case "result":
            return .finished(message.result ?? "")
        default:
            return nil
        }
    }

    /// One line of `--input-format stream-json`.
    public static func userMessage(_ text: String) throws -> Data {
        let message = ["type": "user", "message": ["role": "user", "content": text]] as [String: Any]
        return try JSONSerialization.data(withJSONObject: message) + Data("\n".utf8)
    }

    private struct Message: Decodable {
        let type: String
        let event: Event?
        let result: String?
    }

    private struct Event: Decodable {
        let delta: Delta?
    }

    private struct Delta: Decodable {
        let type: String?
        let text: String?
    }
}
