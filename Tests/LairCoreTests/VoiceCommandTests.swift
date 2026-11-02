import Testing
@testable import LairCore

@Suite struct VoiceCommandTests {
    @Test(arguments: [
        ("Okay, switch to Opus.", VoiceCommand.model("opus")),
        ("Use Sonnet please", .model("sonnet")),
        ("Change the model to GPT 6 Luna", .model("gpt-6-luna")),
        ("Switch to claude opus 5", .model("claude-opus-5")),
        ("Can you go with haiku", .model("haiku")),
        ("Set the model to sonnet", .model("sonnet")),
        ("Think harder.", .thinkMore),
        ("Think more", .thinkMore),
        ("More thinking", .thinkMore),
        ("think deeper", .thinkMore),
        ("Think less", .thinkLess),
        ("Less thinking.", .thinkLess),
        ("Stop overthinking", .thinkLess),
        ("Set thinking to high", .thinking("high")),
        ("Think high", .thinking("high")),
        ("Thinking off", .thinking("off")),
        ("Use max thinking", .thinking("max")),
        ("Extra high thinking", .thinking("xhigh")),
        ("thinking level x high", .thinking("xhigh")),
        ("Effort max", .thinking("max")),
        ("Low effort", .thinking("low")),
        ("Set effort to medium", .thinking("medium")),
        ("Go fast", .fast),
        ("Fast mode.", .fast),
        ("Be quick", .fast),
        ("Quick mode", .fast),
        ("Go deep", .deep),
        ("Deep mode", .deep),
        ("Take your time, thanks", .deep),
        ("Be brief.", .answers(.brief)),
        ("Shorter answers please", .answers(.brief)),
        ("short answers", .answers(.brief)),
        ("More detail", .answers(.detailed)),
        ("more details.", .answers(.detailed)),
        ("Longer answers", .answers(.detailed)),
        ("Be more detailed", .answers(.detailed)),
        ("Normal answers", .answers(.normal)),
        ("Go silent", .silent(true)),
        ("Silent mode.", .silent(true)),
        ("Okay, go silent please", .silent(true)),
        ("Speak again", .silent(false)),
        ("Talk to me again.", .silent(false)),
    ])
    func positives(_ input: String, _ expected: VoiceCommand) {
        #expect(VoiceCommand.parse(input, language: .english) == expected)
    }

    @Test(arguments: [
        "Why is Opus slower than Sonnet?",
        "Switch the API to use haiku embeddings for the search index",
        "Use it",
        "Switch to the other one",
        "Switch to that",
        "Think about the login bug",
        "Go fast on the migration and tell me when it's done",
        "What model are you using?",
        "Tell me more about it",
        "Be brief about the migration and then deploy it",
        "Normal answers?",
        "Can you use sonnet?",
        "How do I switch to opus",
        "Go silent on the logger tests",
        "Why go silent?",
        "Is silent mode on",
        "Speak again later about the migration",
        "Silent",
        "Talk to me",
        "",
    ])
    func negatives(_ input: String) {
        #expect(VoiceCommand.parse(input, language: .english) == nil)
    }

    @Test(arguments: [
        ("Passe à Opus.", VoiceCommand.model("opus")),
        ("Passe sur sonnet s'il te plaît", .model("sonnet")),
        ("Bascule sur claude opus 5", .model("claude-opus-5")),
        ("Change de modèle pour haiku", .model("haiku")),
        ("Réfléchis plus.", .thinkMore),
        ("Reflechis davantage", .thinkMore),
        ("Réfléchis moins", .thinkLess),
        ("Mode rapide", .fast),
        ("Sois rapide, merci", .fast),
        ("Prends ton temps.", .deep),
        ("Sois bref", .answers(.brief)),
        ("Ok, sois bref", .answers(.brief)),
        ("Réponses courtes", .answers(.brief)),
        ("Plus de détails", .answers(.detailed)),
        ("Donne plus de détails s'il te plaît", .answers(.detailed)),
        ("Réponses normales", .answers(.normal)),
        ("Mode silencieux", .silent(true)),
        ("Tais-toi", .silent(true)),
        ("Reparle-moi", .silent(false)),
        ("Mode vocal.", .silent(false)),
    ] as [(String, VoiceCommand?)])
    func frenchCommands(_ input: String, _ expected: VoiceCommand?) {
        #expect(VoiceCommand.parse(input, language: .french) == expected)
    }

    @Test(arguments: [
        "Sois bref sur la migration",
        "Passe à autre chose",
        "Passe à la suite",
        "Passe à la question suivante",
        "Passe à ça",
        "Pourquoi passer à opus",
        "Est-ce que tu réfléchis plus quand c'est dur ?",
        "Qu'est-ce que le mode rapide ?",
        "Réfléchis plus à la migration de la base",
        "Mode silencieux pour les tests du logger",
        "Reparle-moi demain de la migration",
        "Silence",
        "Parle-moi",
        "",
    ])
    func frenchNegatives(_ input: String) {
        #expect(VoiceCommand.parse(input, language: .french) == nil)
    }

    @Test func eachLanguageHearsOnlyItself() {
        #expect(VoiceCommand.parse("Sois bref", language: .english) == nil)
        #expect(VoiceCommand.parse("Be brief", language: .french) == nil)
        #expect(VoiceCommand.parse("Switch to opus", language: .french) == nil)
        #expect(VoiceCommand.parse("Set thinking to high", language: .french) == nil)
    }
}
