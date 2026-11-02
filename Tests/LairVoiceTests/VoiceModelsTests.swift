import FluidAudio
import Foundation
@testable import LairVoice
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

    @Test func uninstallListsTheChainThisOSLoads() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        func kokoro(_ major: Int) -> String {
            VoiceModels.folders(for: OperatingSystemVersion(majorVersion: major, minorVersion: 0, patchVersion: 0))
                .last!.path.replacingOccurrences(of: home, with: "~")
        }
        #expect(kokoro(26) == "~/.cache/fluidaudio/Models/kokoro-82m-coreml/ANE-v3")
        #expect(kokoro(27) == "~/.cache/fluidaudio/Models/kokoro-82m-coreml/ANE")
    }

    @Test func macOS27AndLaterAvoidTheGpuBoundChain() {
        func version(_ major: Int, _ minor: Int) -> KokoroAneVersion {
            VoiceModels.kokoroVersion(for: OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: 0))
        }
        #expect(version(15, 0) == .v3)
        #expect(version(26, 6) == .v3)
        #expect(version(27, 0) == .legacy)
        #expect(version(28, 0) == .legacy)
    }
}
