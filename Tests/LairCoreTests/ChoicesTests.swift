import LairCore
import Testing

@Suite struct ChoicesTests {
    private let colors = ["Red", "Green", "Blue"]

    @Test func anAnswerPicksTheChoiceItNames() {
        #expect(Choices.pick("blue", from: colors) == "Blue")
        #expect(Choices.pick("Let's go with green, please.", from: colors) == "Green")
        #expect(Choices.pick("Before tax", from: ["Before tax", "After tax"]) == "Before tax")
        #expect(Choices.pick("I think after tax is right", from: ["Before tax", "After tax"]) == "After tax")
    }

    @Test func orTheOneItsNumberPointsAt() {
        #expect(Choices.pick("the second one", from: colors) == "Green")
        #expect(Choices.pick("3", from: colors) == "Blue")
        #expect(Choices.pick("Option one.", from: colors) == "Red")
    }

    /// "the blue one" names blue; its "one" isn't the first choice.
    @Test func aNameWinsOverANumber() {
        #expect(Choices.pick("the blue one", from: colors) == "Blue")
    }

    @Test func anythingElseGoesToTheAgentAsSaid() {
        #expect(Choices.pick("purple", from: colors) == nil)
        #expect(Choices.pick("red or blue, I can't decide", from: colors) == nil)
        #expect(Choices.pick("the fifth", from: colors) == nil)
        #expect(Choices.pick("", from: colors) == nil)
        #expect(Choices.pick("blue", from: []) == nil)
    }

    @Test func theChoicesAreSaidWhenTheQuestionDoesntNameThem() {
        #expect(Choices.spoken(colors, after: "Which colour should the subtitle be?") == "Red, Green or Blue.")
        #expect(Choices.spoken(colors, after: "Red, green or blue for the subtitle?") == nil)
        #expect(Choices.spoken(["Yes"], after: "Ship it?") == nil)
    }
}
