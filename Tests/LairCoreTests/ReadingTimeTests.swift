import LairCore
import Testing

struct ReadingTimeTests {
    @Test func aShortAnswerGetsTheBaseTimePlusAWhilePerCharacter() {
        #expect(ReadingTime.duration(for: "") == .seconds(3))
        #expect(ReadingTime.duration(for: String(repeating: "a", count: 100)) == .seconds(8))
    }

    @Test func aLongAnswerIsHeldNoLongerThanTheCap() {
        #expect(ReadingTime.duration(for: String(repeating: "a", count: 240)) == .seconds(15))
        #expect(ReadingTime.duration(for: String(repeating: "a", count: 5_000)) == .seconds(15))
    }
}
