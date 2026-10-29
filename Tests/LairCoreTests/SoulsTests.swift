import Foundation
import LairCore
import Testing

struct SoulsTests {
    private let souls = Souls(folder: FileManager.default.temporaryDirectory.appending(path: "lair-souls-\(UUID().uuidString)"))

    @Test func savesReadsAndRemovesASoulPerAgent() throws {
        defer { try? FileManager.default.removeItem(at: souls.folder) }
        #expect(souls.soul(for: "claude") == nil)
        try souls.save("  Calm and precise.\n", for: "claude")
        try souls.save("Playful.", for: "claude-research")
        #expect(souls.soul(for: "claude") == "Calm and precise.")
        #expect(souls.soul(for: "claude-research") == "Playful.")
        try souls.save("   ", for: "claude")
        #expect(souls.soul(for: "claude") == nil)
        #expect(!FileManager.default.fileExists(atPath: souls.url(for: "claude").path))
    }

    @Test func addsNameAndSoulToTheVoiceRules() {
        let prompt = VoicePrompt.forCall(name: "Claude", soul: "Calm and precise.")
        #expect(prompt.hasPrefix(VoicePrompt.text))
        #expect(prompt.contains("calls you Claude"))
        #expect(prompt.hasSuffix("Calm and precise."))
        #expect(VoicePrompt.forCall(name: nil, soul: nil) == VoicePrompt.text)
    }

    @Test func namesTheOtherAgentsAndHowToReachThem() {
        let prompt = VoicePrompt.forCall(name: "Sage", soul: nil, others: ["Claude", "Nova"])
        #expect(prompt.contains("Claude, Nova"))
        #expect(prompt.contains("\"ask <name> …\""))
    }

    @Test func offersStartersWithText() {
        #expect(Souls.starters.count >= 3)
        #expect(Souls.starters.allSatisfy { !$0.text.isEmpty })
    }
}
