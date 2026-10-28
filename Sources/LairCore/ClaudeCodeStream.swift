import Foundation

public enum AgentEvent: Equatable, Sendable {
    case textDelta(String)
    case approval(ApprovalRequest)
    case finished(String)
    case failed(String)
    /// Which model and thinking level the agent runs.
    case details(String)
    case activity(Activity)
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
        case "system" where message.subtype == "init":
            return agentDetails(model: message.model, thinking: nil).map(AgentEvent.details)
        case "control_request":
            return approval(from: data).map(AgentEvent.approval)
        case "control_response":
            // A model switch answers with the model it resolved to.
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let answer = (object?["response"] as? [String: Any])?["response"] as? [String: Any]
            return (answer?["model"] as? String).flatMap { agentDetails(model: $0, thinking: nil) }.map(AgentEvent.details)
        case "result":
            return .finished(message.result ?? "")
        default:
            return nil
        }
    }

    /// Every event in a line: one line can carry several tool calls, or the usage and the end of the turn.
    public static func parseAll(line: String) -> [AgentEvent] {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String
        else { return [] }
        let content = ((object["message"] as? [String: Any])?["content"] as? [[String: Any]]) ?? []
        switch type {
        case "stream_event":
            let delta = (object["event"] as? [String: Any])?["delta"] as? [String: Any]
            if delta?["type"] as? String == "thinking_delta" {
                guard let text = delta?["thinking"] as? String, !text.isEmpty else { return [] }
                return [.activity(.thinking(text))]
            }
        case "assistant":
            // Text arrives as deltas already; only the tool calls are new here.
            return content.filter { $0["type"] as? String == "tool_use" }.flatMap(toolCall)
        case "user":
            return content.filter { $0["type"] as? String == "tool_result" }.compactMap(toolResult)
        case "result":
            return [usage(object)].compactMap { $0 } + [parse(line: line)].compactMap { $0 }
        default:
            break
        }
        return [parse(line: line)].compactMap { $0 }
    }

    private static func toolCall(_ block: [String: Any]) -> [AgentEvent] {
        guard let id = block["id"] as? String, let name = block["name"] as? String else { return [] }
        let input = block["input"] as? [String: Any] ?? [:]
        let started = AgentEvent.activity(.toolStarted(id: id, name: name, input: readable(input, tool: name)))
        guard name == "Task" || name == "Agent" else { return [started] }
        return [started, .activity(.helper("Started a helper: \(input["description"] as? String ?? name)"))]
    }

    /// The one argument that says what a tool call does, instead of its whole JSON.
    static func readable(_ input: [String: Any], tool: String) -> String {
        let string = { (key: String) in input[key] as? String }
        let pick: String? = switch tool {
        case "Bash": string("command")
        case "Read", "Write", "Edit", "MultiEdit": string("file_path")
        case "NotebookEdit": string("notebook_path")
        case "Grep", "Glob": string("pattern").map { pattern in string("path").map { "\(pattern) in \($0)" } ?? pattern }
        case "WebFetch": string("url")
        case "WebSearch": string("query")
        case "Task", "Agent": string("description")
        default: nil
        }
        if let pick { return pick }
        let json = (try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys]))
            .map { String(decoding: $0, as: UTF8.self) } ?? ""
        return json.count > 200 ? String(json.prefix(200)) + "…" : json
    }

    private static func toolResult(_ block: [String: Any]) -> AgentEvent? {
        guard let id = block["tool_use_id"] as? String else { return nil }
        let text: String = switch block["content"] {
        case let string as String: string
        case let parts as [[String: Any]]: parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
        default: ""
        }
        return .activity(.toolFinished(id: id, output: Activity.trimmed(text), failed: block["is_error"] as? Bool ?? false))
    }

    private static func usage(_ result: [String: Any]) -> AgentEvent? {
        guard let usage = result["usage"] as? [String: Any] else { return nil }
        let count = { (key: String) in usage[key] as? Int ?? 0 }
        return .activity(.usage(
            inputTokens: count("input_tokens") + count("cache_read_input_tokens") + count("cache_creation_input_tokens"),
            outputTokens: count("output_tokens"), cost: result["total_cost_usd"] as? Double))
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

    public static func setModelRequest(_ model: String) throws -> Data {
        try line(["type": "control_request", "request_id": "lair-\(UUID().uuidString)",
                  "request": ["subtype": "set_model", "model": model]])
    }

    public static func interruptRequest() throws -> Data {
        try line(["type": "control_request", "request_id": "lair-\(UUID().uuidString)", "request": ["subtype": "interrupt"]])
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
        let subtype: String?
        let model: String?
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
