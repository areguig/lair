import Foundation
import LairCore
@testable import LairVoice
import Testing

struct VoiceModelsTests {
    @Test func listsOnlyTheModelFoldersLairLoads() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let folders = VoiceModels.folders.map { $0.path.replacingOccurrences(of: home, with: "~") }
        #expect(folders == ["~/Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v3",
                            "~/Library/Application Support/FluidAudio/Models/silero-vad",
                            "~/Library/Application Support/Lair/pocket"])
    }

    @Test func eachLanguageIsSpokenByItsOwnModel() {
        #expect(VoiceModels.model(for: .english) == "english_18m_2026-10")
        #expect(VoiceModels.model(for: .french) == "french")
    }
}
