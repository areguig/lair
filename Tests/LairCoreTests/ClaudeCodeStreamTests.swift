import Foundation
@testable import LairCore
import Testing

struct ClaudeCodeStreamTests {
    @Test func readsTextDeltas() {
        let line = #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}}"#
        #expect(ClaudeCodeStream.parse(line: line) == .textDelta("Hello"))
    }

    @Test func readsTheFinalResult() {
        let line = #"{"type":"result","subtype":"success","result":"Hello there."}"#
        #expect(ClaudeCodeStream.parse(line: line) == .finished("Hello there."))
    }

    @Test func writesOneUserMessagePerLine() throws {
        let line = String(decoding: try ClaudeCodeStream.userMessage("Say \"hi\"\nplease"), as: UTF8.self)
        #expect(line.hasSuffix("}\n"))
        #expect(line.dropLast().contains("\n") == false)
        let decoded = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        let message = decoded?["message"] as? [String: String]
        #expect(decoded?["type"] as? String == "user")
        #expect(message == ["role": "user", "content": "Say \"hi\"\nplease"])
    }

    @Test func ignoresOtherEventsAndGarbage() {
        #expect(ClaudeCodeStream.parse(line: #"{"type":"system","subtype":"init"}"#) == nil)
        #expect(ClaudeCodeStream.parse(line: #"{"type":"stream_event","event":{"delta":{"type":"input_json_delta"}}}"#) == nil)
        #expect(ClaudeCodeStream.parse(line: "not json") == nil)
    }
}

struct ClaudeCodeApprovalTests {
    private let request = #"{"type":"control_request","request_id":"r1","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"touch a.txt","description":"Create a.txt"},"description":"Create empty file a.txt"}}"#

    @Test func readsAToolApprovalRequest() throws {
        guard case .approval(let approval) = ClaudeCodeStream.parse(line: request) else {
            Issue.record("not an approval")
            return
        }
        #expect(approval.id == "r1")
        #expect(approval.tool == "Bash")
        #expect(approval.summary == "Create empty file a.txt")
    }

    @Test func fallsBackToTheCommandWhenThereIsNoDescription() {
        let line = #"{"type":"control_request","request_id":"r2","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"ls"}}}"#
        guard case .approval(let approval) = ClaudeCodeStream.parse(line: line) else {
            Issue.record("not an approval")
            return
        }
        #expect(approval.summary == "ls")
    }

    @Test func allowSendsTheInputBackUnchanged() throws {
        guard case .approval(let approval) = ClaudeCodeStream.parse(line: request) else { return }
        let line = try ClaudeCodeStream.approvalResponse(approval, decision: .allowOnce)
        let object = try JSONSerialization.jsonObject(with: line) as? [String: Any]
        let response = object?["response"] as? [String: Any]
        let decision = response?["response"] as? [String: Any]
        #expect(object?["type"] as? String == "control_response")
        #expect(response?["request_id"] as? String == "r1")
        #expect(decision?["behavior"] as? String == "allow")
        #expect((decision?["updatedInput"] as? [String: String])?["command"] == "touch a.txt")
        #expect(decision?["updatedPermissions"] == nil)
    }

    private let suggested = #"{"type":"control_request","request_id":"r3","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"mkdir -p out"},"permission_suggestions":[{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"mkdir -p out"}],"behavior":"allow","destination":"localSettings"}]}}"#

    @Test func readsPermissionSuggestions() {
        guard case .approval(let approval) = ClaudeCodeStream.parse(line: suggested) else { return }
        #expect(approval.canAlwaysAllow)
        #expect(!(ApprovalRequest(id: "a", tool: "Bash", summary: "x").canAlwaysAllow))
        #expect(!(ApprovalRequest(id: "a", tool: "Bash", summary: "x", suggestions: Data("[]".utf8)).canAlwaysAllow))
        if case .approval(let plain) = ClaudeCodeStream.parse(line: request) { #expect(!plain.canAlwaysAllow) }
    }

    @Test func emptySuggestionsCannotBeAlwaysAllowed() {
        let line = #"{"type":"control_request","request_id":"r4","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{},"permission_suggestions":[]}}"#
        guard case .approval(let approval) = ClaudeCodeStream.parse(line: line) else { return }
        #expect(!approval.canAlwaysAllow)
    }

    @Test func alwaysAllowSendsTheSuggestionsBack() throws {
        guard case .approval(let approval) = ClaudeCodeStream.parse(line: suggested) else { return }
        let object = try JSONSerialization.jsonObject(with: ClaudeCodeStream.approvalResponse(approval, decision: .allowAlways))
        let decision = ((object as? [String: Any])?["response"] as? [String: Any])?["response"] as? [String: Any]
        #expect(decision?["behavior"] as? String == "allow")
        let sent = decision?["updatedPermissions"] as? [[String: Any]]
        let want = try JSONSerialization.jsonObject(with: #"[{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"mkdir -p out"}],"behavior":"allow","destination":"localSettings"}]"#.data(using: .utf8)!) as? [[String: Any]]
        #expect((sent as NSArray?)?.isEqual(to: want ?? []) == true)
    }

    @Test func alwaysAllowWithoutSuggestionsActsLikeAllowOnce() throws {
        guard case .approval(let approval) = ClaudeCodeStream.parse(line: request) else { return }
        let object = try JSONSerialization.jsonObject(with: ClaudeCodeStream.approvalResponse(approval, decision: .allowAlways))
        let decision = ((object as? [String: Any])?["response"] as? [String: Any])?["response"] as? [String: Any]
        #expect(decision?["behavior"] as? String == "allow")
        #expect(decision?["updatedPermissions"] == nil)
    }

    @Test func denySaysTheUserSaidNo() throws {
        guard case .approval(let approval) = ClaudeCodeStream.parse(line: request) else { return }
        let object = try JSONSerialization.jsonObject(with: ClaudeCodeStream.approvalResponse(approval, decision: .deny))
        let decision = ((object as? [String: Any])?["response"] as? [String: Any])?["response"] as? [String: Any]
        #expect(decision?["behavior"] as? String == "deny")
        #expect(decision?["message"] as? String == "The user said no.")
    }

    @Test func ignoresOtherControlRequests() {
        #expect(ClaudeCodeStream.parse(line: #"{"type":"control_request","request_id":"x","request":{"subtype":"interrupt"}}"#) == nil)
    }
}

struct ClaudeCodeActivityTests {
    @Test func readsThinkingDeltas() {
        let line = #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"Let me check."}}}"#
        #expect(ClaudeCodeStream.parseAll(line: line) == [.activity(.thinking("Let me check."))])
    }

    @Test func readsEveryToolCallOfAMessageAndIgnoresItsText() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"text","text":"On it."},{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"swift test","description":"Run tests"}},{"type":"tool_use","id":"t2","name":"Task","input":{"description":"Review the diff","prompt":"…"}}]}}"#
        #expect(ClaudeCodeStream.parseAll(line: line) == [
            .activity(.toolStarted(id: "t1", name: "Bash", input: "swift test")),
            .activity(.toolStarted(id: "t2", name: "Task", input: "Review the diff")),
            .activity(.helper("Started a helper: Review the diff")),
        ])
    }

    @Test func summarizesToolInputsReadably() {
        #expect(ClaudeCodeStream.readable(["file_path": "/a/b.swift"], tool: "Edit") == "/a/b.swift")
        #expect(ClaudeCodeStream.readable(["pattern": "TODO", "path": "Sources"], tool: "Grep") == "TODO in Sources")
        #expect(ClaudeCodeStream.readable(["x": 1], tool: "mcp__thing") == #"{"x":1}"#)
    }

    @Test func readsToolResultsAsTextOrBlocks() {
        let text = #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"ok","is_error":false}]}}"#
        let blocks = #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t2","content":[{"type":"text","text":"line 1"},{"type":"text","text":"line 2"}],"is_error":true}]}}"#
        #expect(ClaudeCodeStream.parseAll(line: text) == [.activity(.toolFinished(id: "t1", output: "ok", failed: false))])
        #expect(ClaudeCodeStream.parseAll(line: blocks) == [.activity(.toolFinished(id: "t2", output: "line 1\nline 2", failed: true))])
    }

    @Test func reportsUsageBeforeTheTurnEnds() {
        let line = #"{"type":"result","subtype":"success","result":"Done.","usage":{"input_tokens":10,"cache_read_input_tokens":900,"cache_creation_input_tokens":90,"output_tokens":42},"total_cost_usd":0.0123}"#
        #expect(ClaudeCodeStream.parseAll(line: line) == [
            .activity(.usage(inputTokens: 1000, outputTokens: 42, cost: 0.0123)),
            .finished("Done."),
        ])
    }

    @Test func keepsTheSingleEventsAsBefore() {
        let line = #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Hi"}}}"#
        #expect(ClaudeCodeStream.parseAll(line: line) == [.textDelta("Hi")])
    }
}
