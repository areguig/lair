import Foundation

/// The part of ACP v1 that Lair speaks, as the official schema defines it
/// (https://agentclientprotocol.com, `schema/v1/schema.json` in @agentclientprotocol/sdk).
/// Unknown fields are ignored and unknown session updates decode as `.other`, so newer agents still work.
enum ACPWire {
    static let protocolVersion = 1

    struct Implementation: Codable, Equatable {
        let name: String
        let version: String
    }

    struct InitializeParams: Encodable {
        let protocolVersion = ACPWire.protocolVersion
        let clientCapabilities = ClientCapabilities()
        let clientInfo: Implementation
    }

    /// Lair reads no files and runs no terminals for the agent.
    struct ClientCapabilities: Encodable {
        let fs = FileSystem()
        let terminal = false

        struct FileSystem: Encodable {
            let readTextFile = false
            let writeTextFile = false
        }
    }

    struct InitializeResult: Decodable {
        let protocolVersion: Int
        let agentInfo: Implementation?
    }

    struct NewSessionParams: Encodable {
        let cwd: String
        let mcpServers: [MCPServer]
    }

    /// An MCP server the agent connects to for this session, over HTTP.
    struct MCPServer: Encodable, Equatable {
        let type = "http"
        let name: String
        let url: String
        let headers: [Header]

        struct Header: Encodable, Equatable {
            let name: String
            let value: String
        }
    }

    struct NewSessionResult: Decodable, Sendable {
        let sessionId: String
        let configOptions: [ConfigOption]

        private enum CodingKeys: String, CodingKey { case sessionId, configOptions }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            sessionId = try container.decode(String.self, forKey: .sessionId)
            configOptions = try container.decodeIfPresent([LossyOption].self, forKey: .configOptions)?.compactMap(\.option) ?? []
        }
    }

    struct PromptParams: Encodable {
        let sessionId: String
        let prompt: [TextBlock]
    }

    struct TextBlock: Codable, Equatable {
        var type = "text"
        let text: String
    }

    struct PromptResult: Decodable {
        let stopReason: String
        /// Not in the stable schema yet, but Claude Code, omp and Hermes all send it.
        let usage: Usage?

        struct Usage: Decodable {
            let inputTokens: Int?
            let outputTokens: Int?
            let cachedReadTokens: Int?
            let cachedWriteTokens: Int?
        }
    }

    struct SessionParams: Encodable {
        let sessionId: String
    }

    struct SetConfigOptionParams: Encodable {
        let sessionId: String
        let configId: String
        let value: String
    }

    struct ConfigOptionsResult: Decodable {
        let configOptions: [ConfigOption]

        private enum CodingKeys: String, CodingKey { case configOptions }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            configOptions = try container.decode([LossyOption].self, forKey: .configOptions).compactMap(\.option)
        }
    }

    /// A dropdown the agent offers, such as its model or thinking level; on/off toggles are left out.
    struct ConfigOption: Decodable, Equatable, Sendable {
        let id: String
        let name: String
        let category: String?
        let currentValue: String
        let values: [Value]

        struct Value: Decodable, Equatable, Sendable {
            let value: String
            let name: String
        }

        private enum CodingKeys: String, CodingKey { case id, name, category, type, currentValue, options }

        /// Options come as a flat list or in groups; Lair only needs the values.
        private struct Group: Decodable {
            let options: [Value]
        }

        init(id: String, name: String, category: String?, currentValue: String, values: [Value]) {
            (self.id, self.name, self.category, self.currentValue, self.values) = (id, name, category, currentValue, values)
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard try container.decode(String.self, forKey: .type) == "select" else {
                throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "not a select")
            }
            id = try container.decode(String.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
            category = try container.decodeIfPresent(String.self, forKey: .category)
            currentValue = try container.decode(String.self, forKey: .currentValue)
            if let flat = try? container.decode([Value].self, forKey: .options) {
                values = flat
            } else {
                values = try container.decode([Group].self, forKey: .options).flatMap(\.options)
            }
        }
    }

    struct SessionNotification: Decodable {
        let sessionId: String
        let update: SessionUpdate
    }

    enum SessionUpdate: Decodable, Equatable {
        case agentText(String)
        case agentThought(String)
        case toolCall(id: String, title: String, input: String)
        case toolCallUpdate(id: String, status: String?, output: String)
        case configOptions([ConfigOption])
        case other

        private enum CodingKeys: String, CodingKey {
            case sessionUpdate, content, toolCallId, title, status, rawInput, configOptions
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(String.self, forKey: .sessionUpdate) {
            case "agent_message_chunk":
                self = (try? container.decode(TextBlock.self, forKey: .content)).map { .agentText($0.text) } ?? .other
            case "agent_thought_chunk":
                self = (try? container.decode(TextBlock.self, forKey: .content)).map { .agentThought($0.text) } ?? .other
            case "tool_call":
                self = .toolCall(id: try container.decode(String.self, forKey: .toolCallId),
                                 title: (try? container.decode(String.self, forKey: .title)) ?? "tool",
                                 input: (try? container.decode(JSONText.self, forKey: .rawInput))?.text ?? "")
            case "tool_call_update":
                let content = (try? container.decode([ToolContent].self, forKey: .content)) ?? []
                self = .toolCallUpdate(id: try container.decode(String.self, forKey: .toolCallId),
                                       status: try? container.decode(String.self, forKey: .status),
                                       output: content.compactMap(\.content?.text).joined(separator: "\n"))
            case "config_option_update":
                self = .configOptions((try? container.decode([LossyOption].self, forKey: .configOptions))?.compactMap(\.option) ?? [])
            default:
                self = .other
            }
        }

        /// `{"type": "content", "content": {"type": "text", "text": …}}`; diffs and terminals are skipped.
        private struct ToolContent: Decodable {
            let content: TextBlock?
        }
    }

    /// Skips options Lair can't use (toggles) instead of failing the whole list.
    struct LossyOption: Decodable {
        let option: ConfigOption?

        init(from decoder: Decoder) throws {
            option = try? ConfigOption(from: decoder)
        }
    }

    struct PermissionRequest: Decodable {
        let sessionId: String
        let toolCall: ToolCall
        let options: [PermissionOption]

        struct ToolCall: Decodable {
            let toolCallId: String
            let title: String?
        }
    }

    struct PermissionOption: Decodable, Equatable, Sendable {
        let optionId: String
        let name: String
        /// allow_once, allow_always, reject_once or reject_always.
        let kind: String
    }

    struct PermissionResult: Encodable {
        let outcome: Outcome

        struct Outcome: Encodable {
            let outcome: String
            let optionId: String?
        }

        static func selected(_ optionId: String) -> PermissionResult {
            PermissionResult(outcome: Outcome(outcome: "selected", optionId: optionId))
        }

        static let cancelled = PermissionResult(outcome: Outcome(outcome: "cancelled", optionId: nil))
    }
}

/// Any JSON value, kept as compact text: a tool's arguments, shown in Mission Control.
struct JSONText: Decodable {
    let text: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            text = string
        } else {
            let value = try container.decode(AnyJSON.self)
            let data = try JSONSerialization.data(withJSONObject: value.value, options: [.sortedKeys, .fragmentsAllowed])
            text = String(decoding: data, as: UTF8.self)
        }
    }
}

/// Decodes any JSON into Foundation values, for passing on unchanged.
struct AnyJSON: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { value = NSNull() }
        else if let bool = try? container.decode(Bool.self) { value = bool }
        else if let number = try? container.decode(Double.self) { value = number }
        else if let string = try? container.decode(String.self) { value = string }
        else if let array = try? container.decode([AnyJSON].self) { value = array.map(\.value) }
        else { value = try container.decode([String: AnyJSON].self).mapValues(\.value) }
    }
}
