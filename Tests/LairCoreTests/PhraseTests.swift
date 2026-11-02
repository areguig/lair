import Testing
@testable import LairCore

@Suite struct PhraseTests {
    @Test func englishIsWhatLairAlwaysSaid() {
        func english(_ phrase: Phrase) -> String { phrase.text(in: .english) }
        #expect(english(.done(agent: "Nova")) == "Nova is done.")
        #expect(english(.needsOKElsewhere(agent: "Nova")) == "Nova needs your OK.")
        #expect(english(.needsOK(agent: "Nova", action: "run the tests", canAlwaysAllow: false))
            == "Nova needs your OK to run the tests. Allow it? Say yes or no.")
        #expect(english(.needsOK(agent: "Nova", action: "run the tests", canAlwaysAllow: true))
            == "Nova needs your OK to run the tests. Allow it? Say yes, always, or no.")
        #expect(english(.sayYesOrNo(canAlwaysAllow: false)) == "Sorry, say yes or no.")
        #expect(english(.sayYesOrNo(canAlwaysAllow: true)) == "Sorry, say yes, always, or no.")
        #expect(english(.approved(.allowOnce, action: "Edit a.txt")) == "Allowed once: Edit a.txt")
        #expect(english(.approved(.allowAlways, action: "Edit a.txt")) == "Always allowed: Edit a.txt")
        #expect(english(.approved(.deny, action: "Edit a.txt")) == "Denied: Edit a.txt")
        #expect(english(.askingAgent("Echo")) == "Asking Echo.")
        #expect(english(.passedOn(to: "Echo")) == "Passed on to Echo.")
        #expect(english(.busy(agent: "Echo")) == "Echo is busy; say it again when it's done.")
        #expect(english(.relayedFrom(agent: "Nova", withAnswer: false)) == "From Nova")
        #expect(english(.relayedFrom(agent: "Nova", withAnswer: true)) == "From Nova, with its last answer")
        #expect(english(.backWithNews) == "Back with news")
        #expect(english(.youCutIn) == "You cut in.")
        #expect(english(.didntAnswer(agent: "Nova")) == "Nova didn't answer.")
        #expect(english(.switchedModel("opus")) == "Switched to opus.")
        #expect(english(.thinkingNow("high")) == "Thinking high now.")
        #expect(english(.thinkingNextCall("high")) == "I'll think high from the next call.")
        #expect(english(.answers(.brief)) == "Brief answers for this call.")
        #expect(english(.answers(.detailed)) == "Detailed answers for this call.")
        #expect(english(.silentOn) == "Silent mode: I'll write instead of speaking.")
        #expect(english(.speakingAgain) == "Speaking again.")
        #expect(english(.cantChangeDuringCall) == "That can't change during a call.")
        #expect(english(.choosesItself(agent: "Nova")) == "Nova chooses that itself.")
        #expect(english(.says(speaker: "O M P")) == "O M P says,")
        #expect(english(.asks(speaker: "O M P")) == "O M P asks,")
    }

    @Test func frenchSaysTheSameThingsInFrench() {
        func french(_ phrase: Phrase) -> String { phrase.text(in: .french) }
        #expect(french(.done(agent: "Nova")) == "Nova a fini.")
        #expect(french(.needsOKElsewhere(agent: "Nova")) == "Nova a besoin de ton accord.")
        #expect(french(.sayYesOrNo(canAlwaysAllow: true)) == "Pardon, dis oui, toujours ou non.")
        #expect(french(.approved(.deny, action: "Edit a.txt")) == "Refusé : Edit a.txt")
        #expect(french(.askingAgent("Echo")) == "Je demande à Echo.")
        #expect(french(.passedOn(to: "Echo")) == "Transmis à Echo.")
        #expect(french(.answers(.brief)) == "Réponses brèves pour cet appel.")
        #expect(french(.switchedModel("opus")) == "Je passe à opus.")
        #expect(french(.says(speaker: "O M P")) == "O M P dit,")
        #expect(french(.asks(speaker: "O M P")) == "O M P demande,")
    }

    /// The action is the agent's own English wording, which a French voice would mangle.
    @Test func aFrenchApprovalQuestionLeavesTheActionOnTheScreen() {
        let line = Phrase.needsOK(agent: "Nova", action: "run the tests", canAlwaysAllow: true).text(in: .french)
        #expect(line == "Nova a besoin de ton accord, c'est à l'écran. Tu autorises ? Dis oui, toujours ou non.")
        #expect(Phrase.needsOK(agent: "Nova", action: "x", canAlwaysAllow: false).text(in: .french).hasSuffix("Dis oui ou non."))
    }

    @Test func thinkingLevelsAreSaidInFrench() {
        #expect(Phrase.thinkingNow("high").text(in: .french) == "Réflexion élevée maintenant.")
        #expect(Phrase.thinkingNow("xhigh").text(in: .french) == "Réflexion très élevée maintenant.")
        #expect(Phrase.thinkingNextCall("low").text(in: .french) == "Réflexion faible à partir du prochain appel.")
        // An agent's own level name is kept as it is.
        #expect(Phrase.thinkingNow("ultra").text(in: .french) == "Réflexion ultra maintenant.")
    }
}
