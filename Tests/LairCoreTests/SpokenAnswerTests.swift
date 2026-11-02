import LairCore
import Testing

struct SpokenAnswerTests {
    @Test(arguments: ["Yes.", "Yeah, go ahead.", "Okay", "Sure, do it", "Allow it.", "Yes please."])
    func hearsYes(_ transcript: String) {
        #expect(SpokenAnswer.parse(transcript, language: .english) == .allowOnce)
    }

    @Test(arguments: ["No.", "Nope", "Don't do that.", "Do not allow it", "Stop!", "No, don't do it.", "Cancel"])
    func hearsNo(_ transcript: String) {
        #expect(SpokenAnswer.parse(transcript, language: .english) == .deny)
    }

    @Test(arguments: ["", "What does it do?", "Hmm, let me think", "Know what, maybe"])
    func asksAgainWhenUnclear(_ transcript: String) {
        #expect(SpokenAnswer.parse(transcript, language: .english) == nil)
    }

    @Test(arguments: ["Always", "Always allow", "Yes, always", "Allow always", "Don't ask again", "Dont ask me again"])
    func hearsAlways(_ transcript: String) {
        #expect(SpokenAnswer.parse(transcript, language: .english) == .allowAlways)
    }

    @Test func neverAllowingIsStillNo() {
        #expect(SpokenAnswer.parse("Never allow that", language: .english) == .deny)
    }

    @Test(arguments: ["Oui.", "Ouais, vas-y.", "D'accord", "Bien sûr", "Allez-y", "OK"])
    func hearsFrenchYes(_ transcript: String) {
        #expect(SpokenAnswer.parse(transcript, language: .french) == .allowOnce)
    }

    @Test(arguments: ["Non.", "Non, annule.", "Refuse", "Jamais", "Arrête !", "Annule ça", "Oui, non, finalement"])
    func hearsFrenchNo(_ transcript: String) {
        #expect(SpokenAnswer.parse(transcript, language: .french) == .deny)
    }

    @Test(arguments: ["Toujours", "Oui, toujours", "Ne me demande plus"])
    func hearsFrenchAlways(_ transcript: String) {
        #expect(SpokenAnswer.parse(transcript, language: .french) == .allowAlways)
    }

    @Test func notAlwaysIsNeverAlways() {
        #expect(SpokenAnswer.parse("Pas toujours", language: .french) == nil)
        #expect(SpokenAnswer.parse("Non, jamais toujours", language: .french) == .deny)
    }

    @Test(arguments: ["", "Qu'est-ce que ça fait ?", "Laisse-moi réfléchir", "Je ne sais pas trop"])
    func asksAgainWhenFrenchIsUnclear(_ transcript: String) {
        #expect(SpokenAnswer.parse(transcript, language: .french) == nil)
    }

    @Test func eachLanguageHearsOnlyItself() {
        #expect(SpokenAnswer.parse("Oui", language: .english) == nil)
        #expect(SpokenAnswer.parse("Yes", language: .french) == nil)
    }
}
