@testable import LairCore
import Testing

struct OrbPressTests {
    private func effects(_ inputs: [OrbPress.Input]) -> [OrbPress.Effect?] {
        var press = OrbPress()
        return inputs.map { press.handle($0) }
    }

    @Test func aClickTogglesTalkingOnceNoSecondClickCame() {
        #expect(effects([.down(clicks: 1), .up, .timeout]) == [.wait, .wait, .toggleTalk])
    }

    @Test func holdingTalksUntilYouLetGo() {
        #expect(effects([.down(clicks: 1), .timeout, .up]) == [.wait, .startHold, .endHold])
    }

    @Test func aDoubleClickOpensThePanelWithoutTalking() {
        #expect(effects([.down(clicks: 1), .up, .down(clicks: 2), .timeout, .up])
            == [.wait, .wait, .openPanel, nil, nil])
    }

    @Test func draggingMovesTheOrbWithoutTalking() {
        #expect(effects([.down(clicks: 1), .moved, .timeout, .up]) == [.wait, .drag, nil, nil])
    }

    @Test func movingWhileHoldingKeepsTalking() {
        #expect(effects([.down(clicks: 1), .timeout, .moved, .up]) == [.wait, .startHold, nil, .endHold])
    }

    @Test func startsOverAfterEachGesture() {
        #expect(effects([.down(clicks: 1), .moved, .up, .down(clicks: 1), .up, .timeout])
            == [.wait, .drag, nil, .wait, .wait, .toggleTalk])
    }
}
