@testable import LairCore
import Testing

struct VoicesTests {
    @Test func theCatalogHoldsOnlyLicenceSafeEnglishVoicesWithoutDuplicates() {
        let names = Voices.english.map(\.name)
        #expect(names.count == 19 && Set(names).count == 19)
        #expect(Voices.english.allSatisfy { $0.language == .english })
        // Kyutai's Expresso and EARS recordings are non-commercial.
        #expect(!names.contains("cosette") && !names.contains("jean"))
    }

    @Test func theDefaultComesFirstSoTheFirstAgentGetsIt() {
        #expect(Voices.english.first?.name == Voices.defaultName())
    }

    @Test func englishDefaultsToFantineAndIsInTheCatalog() {
        #expect(Voices.defaultName() == "fantine")
        #expect(Voices.english.contains { $0.name == Voices.defaultName(for: .english) })
    }

    @Test func aKnownVoiceStaysAndAnUnknownOneFallsBackToTheDefault() {
        #expect(Voices.resolve("george") == "george")
        #expect(Voices.resolve("af_heart") == "fantine")
        #expect(Voices.resolve("") == "fantine")
    }

    @Test func labelsReadAsNames() {
        #expect(Voices.english.first { $0.name == "peter_yearsley" }?.label == "Peter Yearsley")
        #expect(Voices.label(for: "alba") == "Alba")
        #expect(Voices.label(for: "bf_emma") == "Fantine")
    }

    @Test func frenchHasEstelleFirstAndOnlyLicenceSafeVoices() {
        let names = Voices.names(for: .french)
        #expect(names.first == "estelle" && Voices.defaultName(for: .french) == "estelle")
        #expect(Set(names).count == names.count && Voices.french.allSatisfy { $0.language == .french })
        #expect(!names.contains("cosette") && !names.contains("jean"))
        // Every French voice is one Kyutai's catalog knows.
        #expect(Set(names.filter { $0 != "estelle" }).isSubset(of: Set(Voices.names(for: .english))))
    }

    @Test func aVoiceOfAnotherLanguageFallsBackToThisLanguagesDefault() {
        #expect(Voices.resolve("estelle", language: .french) == "estelle")
        #expect(Voices.resolve("charles", language: .french) == "charles")
        #expect(Voices.resolve("george", language: .french) == "estelle")
        #expect(Voices.resolve("estelle", language: .english) == "fantine")
        #expect(Voices.label(for: "estelle", language: .french) == "Estelle")
    }

    @Test func eachLanguageIntroducesAVoiceInItsOwnWords() {
        #expect(Language.english.introduction(of: "Atlas") == "Hi, I'm Atlas.")
        #expect(Language.french.introduction(of: "Atlas") == "Bonjour, je suis Atlas.")
        #expect(Language.french.label == "Français")
        #expect(Language(rawValue: "fr") == .french && Language(rawValue: "de") == nil)
    }
}
