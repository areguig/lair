import Foundation
import LairCore
import Testing

struct OmpStreamTests {
    @Test func readsTextDeltas() {
        let line = #"{"type":"message_update","assistantMessageEvent":{"type":"text_delta","contentIndex":0,"delta":"Hi"}}"#
        #expect(OmpStream.parse(line: line) == .event(.textDelta("Hi")))
    }

    @Test func ignoresThinkingAndOtherUpdates() {
        #expect(OmpStream.parse(line: #"{"type":"message_update","assistantMessageEvent":{"type":"thinking_delta","delta":"hmm"}}"#) == nil)
        #expect(OmpStream.parse(line: #"{"type":"agent_end"}"#) == nil)
        #expect(OmpStream.parse(line: "not json") == nil)
    }

    @Test func endsTheTurnOnItsPromptResult() {
        let ok = #"{"type":"prompt_result","id":"p1","agentInvoked":true,"status":"completed","sessionSettled":true}"#
        #expect(OmpStream.parse(line: ok) == .event(.finished("")))
        let failed = #"{"type":"prompt_result","id":"p1","agentInvoked":false,"status":"error","error":{"message":"No API key found"}}"#
        #expect(OmpStream.parse(line: failed) == .event(.failed("No API key found")))
    }

    @Test func turnsAConfirmIntoAnApproval() {
        let line = #"{"type":"extension_ui_request","id":"d1","method":"confirm","title":"Run command?","message":"rm -rf build"}"#
        guard case .event(.approval(let request)) = OmpStream.parse(line: line) else {
            Issue.record("not an approval")
            return
        }
        #expect(request.id == "d1")
        #expect(request.summary == "rm -rf build")
        #expect(request.canAlwaysAllow == false)
    }

    @Test func cancelsDialogsThatCantBeSpokenAndIgnoresTheRest() {
        #expect(OmpStream.parse(line: #"{"type":"extension_ui_request","id":"d2","method":"select","title":"Pick","options":["a"]}"#)
            == .unsupportedDialog(id: "d2"))
        #expect(OmpStream.parse(line: #"{"type":"extension_ui_request","id":"d3","method":"setWidget","widgetKey":"x"}"#) == nil)
    }

    @Test func writesTheCommandsOmpExpects() throws {
        func object(_ data: Data) throws -> [String: Any] {
            try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        }
        let prompt = try object(OmpStream.prompt("Hello", id: "p1"))
        #expect(prompt["type"] as? String == "prompt")
        #expect(prompt["id"] as? String == "p1")
        #expect(prompt["message"] as? String == "Hello")
        #expect(try object(OmpStream.abort())["type"] as? String == "abort")
        #expect(try object(OmpStream.deltaUpdates())["messageUpdates"] as? String == "delta")

        let request = ApprovalRequest(id: "d1", tool: "Run", summary: "x")
        #expect(try object(OmpStream.confirm(request, decision: .allowOnce))["confirmed"] as? Bool == true)
        #expect(try object(OmpStream.confirm(request, decision: .deny))["confirmed"] as? Bool == false)
        #expect(try object(OmpStream.cancelDialog(id: "d2"))["cancelled"] as? Bool == true)
    }
}

struct AgentDetailsTests {
    @Test func readsOmpModelAndThinkingFromItsState() {
        let line = #"{"type":"response","command":"get_state","success":true,"data":{"model":{"id":"gpt-6-luna","provider":"github-copilot"},"thinkingLevel":"low"}}"#
        #expect(OmpStream.parse(line: line) == .event(.details("gpt-6-luna · low thinking")))
        #expect(OmpStream.parse(line: #"{"type":"model_changed"}"#) == .stateChanged)
    }

    @Test func readsClaudeCodesModelFromInit() {
        let line = #"{"type":"system","subtype":"init","model":"claude-haiku-5-5","permissionMode":"default"}"#
        #expect(ClaudeCodeStream.parse(line: line) == .details("claude-haiku-5-5"))
    }

    @Test func leavesOutThinkingWhenOffOrUnknown() {
        #expect(agentDetails(model: "m", thinking: "off") == "m")
        #expect(agentDetails(model: nil, thinking: "high") == "high thinking")
        #expect(agentDetails(model: nil, thinking: nil) == nil)
    }
}
