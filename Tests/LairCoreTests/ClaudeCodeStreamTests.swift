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

    @Test func ignoresOtherEventsAndGarbage() {
        #expect(ClaudeCodeStream.parse(line: #"{"type":"system","subtype":"init"}"#) == nil)
        #expect(ClaudeCodeStream.parse(line: #"{"type":"stream_event","event":{"delta":{"type":"input_json_delta"}}}"#) == nil)
        #expect(ClaudeCodeStream.parse(line: "not json") == nil)
    }
}
