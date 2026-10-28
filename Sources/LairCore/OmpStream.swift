import Foundation

/// Reads and writes the JSON lines of `omp --mode rpc`.
public enum OmpStream {
    public enum Line: Equatable, Sendable {
        case event(AgentEvent)
        /// A dialog Lair can't show by voice; it must be cancelled or omp waits forever.
        case unsupportedDialog(id: String)
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
            guard event?["type"] as? String == "text_delta", let delta = event?["delta"] as? String, !delta.isEmpty
            else { return nil }
            return .event(.textDelta(delta))
        case "prompt_result":
            guard object["status"] as? String == "error" else { return .event(.finished("")) }
            let error = object["error"] as? [String: Any]
            return .event(.failed(error?["message"] as? String ?? "omp couldn't run the prompt."))
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

    /// Asks for text deltas instead of whole message snapshots on every update.
    public static func deltaUpdates() throws -> Data {
        try line(["type": "set_event_filter", "events": NSNull(), "messageUpdates": "delta"])
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
