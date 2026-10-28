import LairCore
import Testing

struct ChatCompletionStreamTests {
    @Test func readsContentDeltasUntilDone() {
        var stream = ChatCompletionStream()
        #expect(stream.feed(#"data: {"choices":[{"delta":{"role":"assistant"}}]}"#) == nil)
        #expect(stream.feed(#"data: {"choices":[{"delta":{"content":"Hi"}}]}"#) == .text("Hi"))
        #expect(stream.feed(#"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#) == nil)
        #expect(stream.feed("data: [DONE]") == .done)
    }

    @Test func skipsToolProgressEventsAndKeepalives() {
        var stream = ChatCompletionStream()
        #expect(stream.feed(": keepalive") == nil)
        #expect(stream.feed("event: hermes.tool.progress") == nil)
        #expect(stream.feed(#"data: {"choices":[{"delta":{"content":"🔧 terminal"}}]}"#) == nil)
        #expect(stream.feed(#"data: {"choices":[{"delta":{"content":"Done."}}]}"#) == .text("Done."))
    }

    @Test func reportsFailedReplies() {
        var stream = ChatCompletionStream()
        #expect(stream.feed(#"data: {"choices":[{"delta":{},"finish_reason":"error"}]}"#) == .failed("error"))
    }
}
