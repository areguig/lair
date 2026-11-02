import Foundation
import LairCore
import Testing

struct SoundSettingsTests {
    @Test func unsetMeansEverythingOnAtFullVolume() {
        let sounds = LairConfig.initial.soundSettings
        #expect(sounds.level == 1)
        #expect(SoundGroup.allCases.allSatisfy(sounds.isOn))
        #expect(sounds.isDefault)
        #expect(!LairConfig.initial.isSilent)
    }

    @Test func switchingAGroupOffAndOnAgainReturnsToTheDefault() {
        var sounds = SoundSettings()
        sounds.set(.done, on: false)
        sounds.set(.problems, on: false)
        #expect(!sounds.isOn(.done) && !sounds.isOn(.problems) && sounds.isOn(.listening))
        #expect(sounds.off == [.done, .problems])
        sounds.set(.done, on: true)
        sounds.set(.problems, on: true)
        #expect(sounds == SoundSettings())
    }

    @Test func fullVolumeIsStoredAsUnsetAndTheLevelStaysInRange() {
        var sounds = SoundSettings()
        sounds.setLevel(0.4)
        #expect(sounds.volume == 0.4 && !sounds.isDefault)
        sounds.setLevel(1)
        #expect(sounds.volume == nil)
        #expect(SoundSettings(volume: 3).level == 1)
        #expect(SoundSettings(volume: -1).level == 0)
    }

    @Test func aConfigWithoutTheNewKeysReadsAndIsWrittenWithoutThem() throws {
        let old = Data(##"{"agents":[],"island":false}"##.utf8)
        let config = try JSONDecoder().decode(LairConfig.self, from: old)
        #expect(config.sounds == nil && config.silent == nil)
        let url = FileManager.default.temporaryDirectory.appending(path: "lair-\(UUID().uuidString)/config.json")
        try config.save(to: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(!text.contains("sounds") && !text.contains("silent"))
    }

    @Test func soundsAndSilentModeSurviveASaveAndLoad() throws {
        var config = LairConfig.initial
        config.sounds = SoundSettings(volume: 0.5, off: [.needsYou])
        config.silent = true
        let url = FileManager.default.temporaryDirectory.appending(path: "lair-\(UUID().uuidString)/config.json")
        try config.save(to: url)
        let loaded = try LairConfig.load(from: url)
        #expect(loaded == config)
        #expect(loaded.isSilent)
        #expect(!loaded.soundSettings.isOn(.needsYou))
    }
}
