import Foundation

public enum AgentEvent: Equatable, Sendable {
    case textDelta(String)
    case approval(ApprovalRequest)
    case finished(String)
}

/// Reads and writes the lines of `claude -p --input-format stream-json --output-format stream-json
/// --include-partial-messages --permission-prompt-tool stdio`.
public enum ClaudeCodeStream {
    public static func parse(line: String) -> AgentEvent? {
        guard let data = line.data(using: .utf8),
              let message = try? JSONDecoder().decode(Message.self, from: data)
        else { return nil }
        switch message.type {
        case "stream_event" where message.event?.delta?.type == "text_delta":
            return message.event?.delta?.text.map(AgentEvent.textDelta)
        case "control_request":
            return approval(from: data).map(AgentEvent.approval)
        case "result":
            return .finished(message.result ?? "")
        default:
            return nil
        }
    }

    /// One line of `--input-format stream-json`.
    public static func userMessage(_ text: String) throws -> Data {
        try line(["type": "user", "message": ["role": "user", "content": text]])
    }

    /// The answer to a `can_use_tool` control request; a deny reaches the model as this message.
    public static func approvalResponse(_ request: ApprovalRequest, decision: ApprovalDecision) throws -> Data {
        var body: [String: Any]
        switch decision {
        case .deny:
            body = ["behavior": "deny", "message": "The user said no."]
        case .allowOnce, .allowAlways:
            body = ["behavior": "allow", "updatedInput": try JSONSerialization.jsonObject(with: request.input)]
            if decision == .allowAlways, request.canAlwaysAllow, let suggestions = request.suggestions {
                body["updatedPermissions"] = try JSONSerialization.jsonObject(with: suggestions)
            }
        }
        return try line(["type": "control_response",
                         "response": ["subtype": "success", "request_id": request.id, "response": body]])
    }

    private static func line(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object) + Data("\n".utf8)
    }

    // Decoded by hand: the tool input is free-form JSON that must be sent back unchanged.
    private static func approval(from data: Data) -> ApprovalRequest? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["request_id"] as? String,
              let request = object["request"] as? [String: Any],
              request["subtype"] as? String == "can_use_tool",
              let tool = request["tool_name"] as? String
        else { return nil }
        let input = request["input"] as? [String: Any] ?? [:]
        let summary = [request["description"], input["description"], input["command"], input["file_path"]]
            .lazy.compactMap { $0 as? String }.first { !$0.isEmpty } ?? "use \(tool)"
        let inputData = (try? JSONSerialization.data(withJSONObject: input)) ?? Data("{}".utf8)
        let suggestions = (request["permission_suggestions"] as? [Any])
            .flatMap { try? JSONSerialization.data(withJSONObject: $0) }
        return ApprovalRequest(id: id, tool: tool, summary: summary, input: inputData, suggestions: suggestions)
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
