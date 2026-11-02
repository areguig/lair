import Testing
@testable import LairCore

@Suite struct VoicePromptTests {
    /// The voice rules as they were before answers could be set.
    private let original = """
        This conversation is a live voice call through Lair: the user speaks, a speech-to-text model writes it down, \
        and everything you write is read aloud by a text-to-speech voice. Talk like a person on the phone.
        - Be concise: one to three short sentences, unless the user asks for more. Lead with the answer.
        - No markdown, lists, tables, headings, emoji or code blocks: they can't be heard.
        - Never read out URLs, file paths, commands, code, hashes, IDs or long numbers. Say what they are instead, \
        like "the config file in your home folder" or "the link I found on the Apple docs".
        - When the user needs to see one of those, wrap it in <show>…</show>: it appears on their screen and is \
        never read aloud. Example: "I updated the config <show>~/.config/app/config.json</show> and restarted it."
        - Round numbers and say units in words. Spell out only what the user must type.
        - When you use tools, don't narrate each step; say briefly what you're doing if it will take a while, \
        then give the result.
        - If the request was likely misheard, ask a short question instead of guessing.
        """

    @Test func normalAnswersAreTheRulesAsTheyWere() {
        #expect(VoicePrompt.text == original)
        #expect(VoicePrompt.forCall(name: nil, soul: nil, answers: .normal) == original)
    }

    @Test func eachLevelReplacesOnlyTheLengthRule() {
        for level in [AgentConfig.Answers.brief, .detailed] {
            let prompt = VoicePrompt.forCall(name: nil, soul: nil, answers: level)
            #expect(prompt == original.replacingOccurrences(of: VoicePrompt.rule(.normal), with: VoicePrompt.rule(level)))
            #expect(prompt.contains("- \(VoicePrompt.rule(level))\n"))
        }
    }

    @Test func theThreeRulesDiffer() {
        #expect(Set(AgentConfig.Answers.allCases.map { VoicePrompt.rule($0) }).count == 3)
    }

    @Test func aMidCallChangeCarriesTheRule() {
        #expect(VoicePrompt.answers(.brief) == "From now on in this call: \(VoicePrompt.rule(.brief))")
        #expect(VoicePrompt.answers(.detailed).hasPrefix("From now on in this call: Explain fully"))
    }

    @Test func englishIsTheDefaultAndNeverChanges() {
        #expect(VoicePrompt.forCall(name: "Nova", soul: "Dry.", others: ["Echo"], answers: .brief)
            == VoicePrompt.forCall(name: "Nova", soul: "Dry.", others: ["Echo"], answers: .brief, language: .english))
        #expect(VoicePrompt.answers(.brief) == VoicePrompt.answers(.brief, language: .english))
    }

    @Test func frenchRulesAreFrenchAndKeepEveryRule() {
        let prompt = VoicePrompt.forCall(name: nil, soul: nil, language: .french)
        #expect(prompt.hasPrefix("Cette conversation est un appel vocal en direct via Lair"))
        #expect(prompt.contains("- \(VoicePrompt.rule(.normal, .french))\n"))
        #expect(prompt.contains("<show>…</show>"))
        #expect(prompt.contains("Pas de markdown"))
        #expect(prompt.contains("Arrondis les nombres"))
        #expect(prompt.contains("mal comprise"))
        #expect(prompt.hasSuffix("(build, commit, pull request…)."))
        #expect(prompt.contains("Réponds toujours en français, quelle que soit la langue de l'utilisateur"))
        #expect(!prompt.contains("This conversation"))
    }

    @Test func frenchAnswerLengthsDifferAndReplaceOnlyTheLengthRule() {
        #expect(Set(AgentConfig.Answers.allCases.map { VoicePrompt.rule($0, .french) }).count == 3)
        let normal = VoicePrompt.forCall(name: nil, soul: nil, language: .french)
        let brief = VoicePrompt.forCall(name: nil, soul: nil, answers: .brief, language: .french)
        #expect(brief == normal.replacingOccurrences(of: VoicePrompt.rule(.normal, .french), with: VoicePrompt.rule(.brief, .french)))
        #expect(VoicePrompt.answers(.brief, language: .french).hasPrefix("À partir de maintenant dans cet appel : Sois très bref"))
    }

    @Test func frenchNameOthersAndSoulAreFrenchToo() {
        let prompt = VoicePrompt.forCall(name: "Nova", soul: "Sèche et drôle.", others: ["Echo", "Claude"], language: .french)
        #expect(prompt.contains("l'utilisateur t'appelle Nova."))
        #expect(prompt.contains("Echo, Claude. Tu ne peux pas les joindre toi-même."))
        #expect(prompt.hasSuffix("Ta personnalité, écrite par l'utilisateur :\nSèche et drôle."))
    }
}
