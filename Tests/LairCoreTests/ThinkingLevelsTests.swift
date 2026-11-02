import Testing

@testable import LairCore

struct ThinkingLevelsTests {
    private let levels = ["low", "medium", "high"]

    @Test func noLevelsMeansNoStep() {
        #expect(ThinkingLevels.step(1, from: "low", in: []) == nil)
    }

    @Test func stepsUpAndDown() {
        #expect(ThinkingLevels.step(1, from: "low", in: levels) == "medium")
        #expect(ThinkingLevels.step(-1, from: "high", in: levels) == "medium")
    }

    @Test func staysAtEitherEnd() {
        #expect(ThinkingLevels.step(1, from: "high", in: levels) == "high")
        #expect(ThinkingLevels.step(-1, from: "low", in: levels) == "low")
    }

    @Test func unknownOrMissingCurrentStartsFromMedium() {
        #expect(ThinkingLevels.step(1, from: nil, in: levels) == "high")
        #expect(ThinkingLevels.step(-1, from: "turbo", in: levels) == "low")
    }

    @Test func withoutMediumStartsFromTheMiddle() {
        let four = ["off", "low", "high", "max"]
        #expect(ThinkingLevels.step(0, from: nil, in: four) == "high")
        #expect(ThinkingLevels.step(1, from: nil, in: four) == "max")
    }
}
