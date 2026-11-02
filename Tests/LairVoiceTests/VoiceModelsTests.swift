import FluidAudio
import Foundation
@testable import LairVoice
import Testing

struct VoiceModelsTests {
    /// Explicit OS versions: CI runs macOS 27 and a developer's Mac may run 26.
    @Test func listsOnlyTheModelFoldersTheChainForThisOSLoads() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        func folders(_ major: Int) -> [String] {
            VoiceModels.folders(for: OperatingSystemVersion(majorVersion: major, minorVersion: 0, patchVersion: 0))
                .map { $0.path.replacingOccurrences(of: home, with: "~") }
        }
        let shared = ["~/Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v2",
                      "~/Library/Application Support/FluidAudio/Models/silero-vad"]
        #expect(folders(26) == shared + ["~/.cache/fluidaudio/Models/kokoro-82m-coreml/ANE-v3"])
        #expect(folders(27) == shared + ["~/.cache/fluidaudio/Models/kokoro-82m-coreml/ANE"])
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
