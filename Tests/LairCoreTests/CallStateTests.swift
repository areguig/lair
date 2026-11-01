import AppKit
import LairCore
import Testing

struct CallStateTests {
    @Test func eachStateHasItsOwnWords() {
        let labels = CallState.allCases.map(\.label)
        #expect(Set(labels).count == labels.count)
        #expect(CallState.thinking.label == "Thinking")
        #expect(CallState.waiting.label == "Needs your OK")
    }

    @Test(arguments: CallState.allCases) func eachSymbolExists(_ state: CallState) {
        #expect(NSImage(systemSymbolName: state.symbol, accessibilityDescription: nil) != nil)
    }
}
