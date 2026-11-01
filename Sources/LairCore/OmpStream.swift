import Foundation

/// Reads and writes the JSON lines of `omp --mode rpc`.
public enum OmpStream {
    public enum Line: Equatable, Sendable {
        case event(AgentEvent)
        /// A dialog Lair can't show by voice; it must be cancelled or omp waits forever.
        case unsupportedDialog(id: String)
        /// The model or thinking level changed: ask for the state again.
        case stateChanged
        /// What `get_available_models` answered.
        case models([OmpModel])
    }

    /// Dialogs that block omp until answered; the rest (notify, widgets, titles) need no answer.
    private static let blockingDialogs: Set<String> = ["select", "input", "editor"]

    public static func parse(line: String) -> Line? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String
        else { return nil }
        switch type {
        case "message_update":
            let event = object["assistantMessageEvent"] as? [String: Any]
            guard let delta = event?["delta"] as? String, !delta.isEmpty else { return nil }
            switch event?["type"] as? String {
            case "text_delta": return .event(.textDelta(delta))
            case "thinking_delta": return .event(.activity(.thinking(delta)))
            default: return nil
            }
        case "message_start":
            // Your prompt entering the run, which may be one omp started itself for a background job.
            let message = object["message"] as? [String: Any]
            return message?["role"] as? String == "user" ? .event(.yourMessage) : nil
        case "agent_end":
            return .event(.idle)
        case "message_end":
            // One assistant message, one usage report (the deltas carry none).
            guard let message = object["message"] as? [String: Any], message["role"] as? String == "assistant",
                  let usage = message["usage"] as? [String: Any]
            else { return nil }
            func count(_ key: String) -> Int { (usage[key] as? NSNumber)?.intValue ?? 0 }
            let cost = ((usage["cost"] as? [String: Any])?["total"] as? NSNumber)?.doubleValue
            return .event(.activity(.usage(
                inputTokens: count("input") + count("cacheRead") + count("cacheWrite"), outputTokens: count("output"), cost: cost)))
        case "tool_execution_start":
            guard let id = object["toolCallId"] as? String, let name = object["toolName"] as? String else { return nil }
            return .event(.activity(.toolStarted(id: id, name: name, input: readable(args: object["args"]))))
        case "tool_execution_end":
            guard let id = object["toolCallId"] as? String else { return nil }
            let output = Activity.trimmed(resultText(object["result"]))
            return .event(.activity(.toolFinished(id: id, output: output, failed: object["isError"] as? Bool ?? false)))
        case "subagent_lifecycle":
            guard let payload = object["payload"] as? [String: Any], let status = payload["status"] as? String else { return nil }
            let agent = payload["agent"] as? String ?? "helper"
            let label = (payload["description"] as? String).map { "\(agent) — \($0)" } ?? agent
            return .event(.activity(.helper(status == "started" ? "Started a helper: \(label)" : "Helper finished: \(label)")))
        case "prompt_result":
            guard object["status"] as? String == "error" else { return .event(.finished("")) }
            let error = object["error"] as? [String: Any]
            return .event(.failed(error?["message"] as? String ?? "omp couldn't run the prompt."))
        case "response" where object["command"] as? String == "get_state":
            let data = object["data"] as? [String: Any]
            let model = (data?["model"] as? [String: Any])?["id"] as? String
            return agentDetails(model: model, thinking: data?["thinkingLevel"] as? String).map { .event(.details($0)) }
        case "model_changed", "thinking_level_changed":
            return .stateChanged
        case "response" where object["command"] as? String == "get_available_models":
            let list = ((object["data"] as? [String: Any])?["models"] as? [[String: Any]]) ?? []
            return .models(list.compactMap { model in
                guard let id = model["id"] as? String, let provider = model["provider"] as? String else { return nil }
                return OmpModel(provider: provider, id: id)
            })
        case "extension_ui_request":
            guard let id = object["id"] as? String, let method = object["method"] as? String else { return nil }
            if method == "confirm" {
                let title = object["title"] as? String ?? "omp"
                let message = object["message"] as? String ?? title
                return .event(.approval(ApprovalRequest(id: id, tool: title, summary: message)))
            }
            return blockingDialogs.contains(method) ? .unsupportedDialog(id: id) : nil
        default:
            return nil
        }
    }

    /// The argument that says most about a tool call, else the arguments as compact JSON.
    private static func readable(args: Any?) -> String {
        guard let args = args as? [String: Any] else { return "" }
        for key in ["command", "path", "file_path", "filePath", "pattern", "url", "query", "description"] {
            if let value = args[key] as? String, !value.isEmpty { return String(value.prefix(200)) }
        }
        guard !args.isEmpty, let data = try? JSONSerialization.data(withJSONObject: args, options: [.sortedKeys]) else { return "" }
        return String(String(decoding: data, as: UTF8.self).prefix(200))
    }

    /// A tool result is a string, or `{content: [{type: "text", text}]}`, or the bare block array.
    private static func resultText(_ result: Any?) -> String {
        if let text = result as? String { return text }
        let blocks = (result as? [String: Any])?["content"] ?? result
        if let text = blocks as? String { return text }
        let parts = (blocks as? [[String: Any]])?.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
        return parts?.joined(separator: "\n") ?? ""
    }

    /// Asks for text deltas instead of whole message snapshots on every update.
    public static func deltaUpdates() throws -> Data {
        try line(["type": "set_event_filter", "events": NSNull(), "messageUpdates": "delta"])
    }

    public static func getAvailableModels() throws -> Data {
        try line(["type": "get_available_models"])
    }

    public static func setModel(_ model: OmpModel) throws -> Data {
        try line(["type": "set_model", "provider": model.provider, "modelId": model.id])
    }

    public static func setThinking(_ level: String) throws -> Data {
        try line(["type": "set_thinking_level", "level": level])
    }

    public static func getState() throws -> Data {
        try line(["type": "get_state"])
    }

    public static func prompt(_ text: String, id: String) throws -> Data {
        try line(["id": id, "type": "prompt", "message": text])
    }

    public static func abort() throws -> Data {
        try line(["type": "abort"])
    }

    public static func confirm(_ request: ApprovalRequest, decision: ApprovalDecision) throws -> Data {
        try line(["type": "extension_ui_response", "id": request.id, "confirmed": decision != .deny])
    }

    public static func cancelDialog(id: String) throws -> Data {
        try line(["type": "extension_ui_response", "id": id, "cancelled": true])
    }

    private static func line(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object) + Data("\n".utf8)
    }
}

public struct OmpModel: Equatable, Sendable {
    public let provider: String
    public let id: String

    public init(provider: String, id: String) {
        self.provider = provider
        self.id = id
    }
}
