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
}
