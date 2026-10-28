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
    ])
    func positives(_ input: String, _ expected: VoiceCommand) {
        #expect(VoiceCommand.parse(input) == expected)
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
        "Can you use sonnet?",
        "How do I switch to opus",
        "",
    ])
    func negatives(_ input: String) {
        #expect(VoiceCommand.parse(input) == nil)
    }
}
