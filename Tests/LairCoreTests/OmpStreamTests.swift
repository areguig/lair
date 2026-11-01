import Foundation
import LairCore
import Testing

struct OmpStreamTests {
    @Test func readsTextDeltas() {
        let line = #"{"type":"message_update","assistantMessageEvent":{"type":"text_delta","contentIndex":0,"delta":"Hi"}}"#
        #expect(OmpStream.parse(line: line) == .event(.textDelta("Hi")))
    }

    @Test func ignoresOtherUpdates() {
        #expect(OmpStream.parse(line: #"{"type":"message_update","assistantMessageEvent":{"type":"toolcall_delta","delta":"{"}}"#) == nil)
        #expect(OmpStream.parse(line: "not json") == nil)
    }

    /// From omp 18.13.3: a run omp starts for a background job opens with its notice, not with your prompt.
    @Test func marksYourPromptEnteringARunAndTheRunsEnd() {
        let yours = #"{"type":"message_start","message":{"role":"user","content":[{"type":"text","text":"Hi"}]}}"#
        #expect(OmpStream.parse(line: yours) == .event(.yourMessage))
        let notice = #"{"type":"message_start","message":{"role":"custom","customType":"async-result","content":"Background job bg_1 has completed."}}"#
        #expect(OmpStream.parse(line: notice) == nil)
        #expect(OmpStream.parse(line: #"{"type":"agent_end","messages":[]}"#) == .event(.idle))
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

struct ModelSwitchTests {
    @Test func readsOmpsAvailableModels() {
        let line = #"{"type":"response","command":"get_available_models","success":true,"data":{"models":[{"id":"gpt-6-luna","provider":"github-copilot","name":"Luna"},{"id":"claude-opus-5.5","provider":"github-copilot"}]}}"#
        #expect(OmpStream.parse(line: line) == .models([
            OmpModel(provider: "github-copilot", id: "gpt-6-luna"), OmpModel(provider: "github-copilot", id: "claude-opus-5.5"),
        ]))
    }

    @Test func writesOmpsSwitchCommands() throws {
        let model = try JSONSerialization.jsonObject(with: OmpStream.setModel(OmpModel(provider: "p", id: "m"))) as? [String: String]
        #expect(model == ["type": "set_model", "provider": "p", "modelId": "m"])
        let thinking = try JSONSerialization.jsonObject(with: OmpStream.setThinking("high")) as? [String: String]
        #expect(thinking == ["type": "set_thinking_level", "level": "high"])
    }

    @Test func readsTheModelClaudeCodeSwitchedTo() {
        let line = #"{"type":"control_response","response":{"subtype":"success","request_id":"r","response":{"model":"claude-sonnet-5-5"}}}"#
        #expect(ClaudeCodeStream.parse(line: line) == .details("claude-sonnet-5-5"))
        #expect(ClaudeCodeStream.parse(line: #"{"type":"control_response","response":{"subtype":"success","request_id":"r"}}"#) == nil)
    }

    @Test func asksClaudeCodeToSwitchModel() throws {
        let object = try JSONSerialization.jsonObject(with: ClaudeCodeStream.setModelRequest("opus")) as? [String: Any]
        let request = object?["request"] as? [String: String]
        #expect(object?["type"] as? String == "control_request")
        #expect(request == ["subtype": "set_model", "model": "opus"])
    }
}

struct OmpActivityTests {
    private func activity(_ line: String) -> Activity? {
        if case .event(.activity(let activity)) = OmpStream.parse(line: line) { return activity }
        return nil
    }

    @Test func readsThinkingDeltas() {
        let line = #"{"type":"message_update","messageId":"m1","message":{"role":"assistant"},"assistantMessageEvent":{"type":"thinking_delta","contentIndex":0,"delta":"Let me look."}}"#
        #expect(activity(line) == .thinking("Let me look."))
    }

    @Test func readsToolStartWithReadableInput() {
        let bash = #"{"type":"tool_execution_start","toolCallId":"c1","toolName":"bash","args":{"command":"ls -la","timeout":5},"intent":"List"}"#
        #expect(activity(bash) == .toolStarted(id: "c1", name: "bash", input: "ls -la"))
        let other = #"{"type":"tool_execution_start","toolCallId":"c2","toolName":"x","args":{"a":1}}"#
        #expect(activity(other) == .toolStarted(id: "c2", name: "x", input: #"{"a":1}"#))
    }

    @Test func readsToolEndFromTextBlocksOrString() {
        let blocks = #"{"type":"tool_execution_end","toolCallId":"c1","toolName":"bash","result":{"content":[{"type":"text","text":"a"},{"type":"text","text":"b"}]},"isError":true}"#
        #expect(activity(blocks) == .toolFinished(id: "c1", output: "a\nb", failed: true))
        let plain = #"{"type":"tool_execution_end","toolCallId":"c1","toolName":"bash","result":"done"}"#
        #expect(activity(plain) == .toolFinished(id: "c1", output: "done", failed: false))
    }

    @Test func readsSubagentLifecycle() {
        let start = #"{"type":"subagent_lifecycle","payload":{"id":"s1","agent":"explore","description":"Find callers","status":"started","index":0}}"#
        #expect(activity(start) == .helper("Started a helper: explore — Find callers"))
        let end = #"{"type":"subagent_lifecycle","payload":{"id":"s1","agent":"explore","status":"completed","index":0}}"#
        #expect(activity(end) == .helper("Helper finished: explore"))
    }

    @Test func readsUsageOnAssistantMessageEnd() {
        let line = #"{"type":"message_end","messageId":"m1","message":{"role":"assistant","content":[],"usage":{"input":100,"output":20,"cacheRead":30,"cacheWrite":5,"totalTokens":155,"cost":{"total":0.0123}}}}"#
        #expect(activity(line) == .usage(inputTokens: 135, outputTokens: 20, cost: 0.0123))
        #expect(activity(#"{"type":"message_end","message":{"role":"user","content":"hi"}}"#) == nil)
    }

    @Test func ignoresUnrelatedEvents() {
        #expect(OmpStream.parse(line: #"{"type":"turn_start"}"#) == nil)
        #expect(OmpStream.parse(line: #"{"type":"subagent_progress","payload":{}}"#) == nil)
        #expect(OmpStream.parse(line: #"{"type":"message_update","assistantMessageEvent":{"type":"toolcall_delta","delta":"{"}}"#) == nil)
    }
}
