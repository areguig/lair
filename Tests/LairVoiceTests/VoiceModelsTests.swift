import Foundation
import LairVoice
import Testing

struct VoiceModelsTests {
    @Test func listsOnlyTheModelFoldersLairLoads() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let folders = VoiceModels.folders.map { $0.path.replacingOccurrences(of: home, with: "~") }
        #expect(folders == [
            "~/Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v2",
            "~/Library/Application Support/FluidAudio/Models/silero-vad",
            "~/.cache/fluidaudio/Models/kokoro-82m-coreml/ANE-v3",
        ])
    }
}
