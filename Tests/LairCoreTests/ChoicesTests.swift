import LairCore
import Testing

@Suite struct ChoicesTests {
    private let colors = ["Red", "Green", "Blue"]

    @Test func anAnswerPicksTheChoiceItNames() {
        #expect(Choices.pick("blue", from: colors, language: .english) == "Blue")
        #expect(Choices.pick("Let's go with green, please.", from: colors, language: .english) == "Green")
        #expect(Choices.pick("Before tax", from: ["Before tax", "After tax"], language: .english) == "Before tax")
        #expect(Choices.pick("I think after tax is right", from: ["Before tax", "After tax"], language: .english) == "After tax")
    }

    @Test func orTheOneItsNumberPointsAt() {
        #expect(Choices.pick("the second one", from: colors, language: .english) == "Green")
        #expect(Choices.pick("3", from: colors, language: .english) == "Blue")
        #expect(Choices.pick("Option one.", from: colors, language: .english) == "Red")
    }

    /// "the blue one" names blue; its "one" isn't the first choice.
    @Test func aNameWinsOverANumber() {
        #expect(Choices.pick("the blue one", from: colors, language: .english) == "Blue")
    }

    @Test func anythingElseGoesToTheAgentAsSaid() {
        #expect(Choices.pick("purple", from: colors, language: .english) == nil)
        #expect(Choices.pick("red or blue, I can't decide", from: colors, language: .english) == nil)
        #expect(Choices.pick("the fifth", from: colors, language: .english) == nil)
        #expect(Choices.pick("", from: colors, language: .english) == nil)
        #expect(Choices.pick("blue", from: [], language: .english) == nil)
    }

    @Test func theChoicesAreSaidWhenTheQuestionDoesntNameThem() {
        #expect(Choices.spoken(colors, after: "Which colour should the subtitle be?", language: .english) == "Red, Green or Blue.")
        #expect(Choices.spoken(colors, after: "Red, green or blue for the subtitle?", language: .english) == nil)
        #expect(Choices.spoken(["Yes"], after: "Ship it?", language: .english) == nil)
    }

    @Test func inFrenchAnAnswerPicksByNumberOrName() {
        let couleurs = ["Rouge", "Vert", "Bleu"]
        #expect(Choices.pick("la deux", from: couleurs, language: .french) == "Vert")
        #expect(Choices.pick("Le deuxième", from: couleurs, language: .french) == "Vert")
        #expect(Choices.pick("Deux.", from: couleurs, language: .french) == "Vert")
        #expect(Choices.pick("la première", from: couleurs, language: .french) == "Rouge")
        #expect(Choices.pick("3", from: couleurs, language: .french) == "Bleu")
        #expect(Choices.pick("Je prends le troisième", from: couleurs, language: .french) == "Bleu")
        #expect(Choices.pick("Plutôt le bleu", from: couleurs, language: .french) == "Bleu")
        #expect(Choices.pick("Avant impôts", from: ["Avant impôts", "Après impôts"], language: .french) == "Avant impôts")
    }

    @Test func inFrenchAnythingElseGoesToTheAgentAsSaid() {
        let couleurs = ["Rouge", "Vert", "Bleu"]
        #expect(Choices.pick("les deux", from: couleurs, language: .french) == nil)
        #expect(Choices.pick("un truc violet", from: couleurs, language: .french) == nil)
        #expect(Choices.pick("la cinquième", from: couleurs, language: .french) == nil)
        #expect(Choices.pick("one", from: couleurs, language: .french) == nil)
    }

    @Test func frenchChoicesAreSaidWithOu() {
        let couleurs = ["Rouge", "Vert", "Bleu"]
        #expect(Choices.spoken(couleurs, after: "Quelle couleur pour le sous-titre ?", language: .french) == "Rouge, Vert ou Bleu.")
        #expect(Choices.spoken(couleurs, after: "Rouge, vert ou bleu ?", language: .french) == nil)
    }
}
