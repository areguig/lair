import Foundation
import LairCore
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
        let line = try ClaudeCodeStream.approvalResponse(approval, allow: true)
        let object = try JSONSerialization.jsonObject(with: line) as? [String: Any]
        let response = object?["response"] as? [String: Any]
        let decision = response?["response"] as? [String: Any]
        #expect(object?["type"] as? String == "control_response")
        #expect(response?["request_id"] as? String == "r1")
        #expect(decision?["behavior"] as? String == "allow")
        #expect((decision?["updatedInput"] as? [String: String])?["command"] == "touch a.txt")
    }

    @Test func denySaysTheUserSaidNo() throws {
        guard case .approval(let approval) = ClaudeCodeStream.parse(line: request) else { return }
        let object = try JSONSerialization.jsonObject(with: ClaudeCodeStream.approvalResponse(approval, allow: false))
        let decision = ((object as? [String: Any])?["response"] as? [String: Any])?["response"] as? [String: Any]
        #expect(decision?["behavior"] as? String == "deny")
        #expect(decision?["message"] as? String == "The user said no.")
    }

    @Test func ignoresOtherControlRequests() {
        #expect(ClaudeCodeStream.parse(line: #"{"type":"control_request","request_id":"x","request":{"subtype":"interrupt"}}"#) == nil)
    }
}
