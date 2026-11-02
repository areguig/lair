import Foundation
@testable import LairVoice
import Testing

struct PocketServerTests {
    private let app = URL(fileURLWithPath: "/Applications/Lair.app")

    @Test func theBundledEngineComesBeforeTheEnvironmentOne() {
        let found = PocketServer.binary(app: app, environment: ["LAIR_POCKET_TTS": "/tmp/pocket-tts"], exists: { _ in true })
        #expect(found?.path == "/Applications/Lair.app/Contents/Helpers/pocket-tts")
    }

    @Test func withoutABundledOneTheEnvironmentNamesIt() {
        let found = PocketServer.binary(app: app, environment: ["LAIR_POCKET_TTS": "/tmp/pocket-tts"], exists: { $0.path == "/tmp/pocket-tts" })
        #expect(found?.path == "/tmp/pocket-tts")
    }

    @Test func noEngineAnywhereIsNil() {
        #expect(PocketServer.binary(app: app, environment: [:], exists: { _ in false }) == nil)
        #expect(PocketServer.binary(app: app, environment: ["LAIR_POCKET_TTS": "/nope"], exists: { _ in false }) == nil)
    }

    @Test func servesOneModelOnLoopbackOnly() {
        #expect(PocketServer.arguments(port: 5123, model: "english_18m_2026-10", defaultVoice: "fantine")
            == ["serve", "--host", "127.0.0.1", "--port", "5123", "--language", "english_18m_2026-10", "--default-voice", "fantine"])
    }

    @Test func aFreePortIsOneYouCanListenOn() throws {
        let port = try PocketServer.freePort()
        #expect(port > 1024 && port <= 65535)
    }

    @Test func modelsLiveInLairsOwnFolder() {
        #expect(PocketServer.home.path.hasSuffix("Library/Application Support/Lair/pocket"))
    }
}
