import Darwin
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

struct PocketLeftoverTests {
    private let binary = URL(fileURLWithPath: "/Applications/Lair.app/Contents/Helpers/pocket-tts")

    @Test func stopsOnlyAProcessRunningTheSameEngine() {
        #expect(PocketServer.shouldStop(pid: 42, pathOfPid: { _ in binary.path }, expectedBinary: binary))
        // The pid was reused by another program, or the process is gone.
        #expect(!PocketServer.shouldStop(pid: 42, pathOfPid: { _ in "/usr/bin/vim" }, expectedBinary: binary))
        #expect(!PocketServer.shouldStop(pid: 42, pathOfPid: { _ in nil }, expectedBinary: binary))
    }

    @Test func aSymlinkedNameForTheSameBinaryCounts() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let real = folder.appending(path: "pocket-tts")
        let link = folder.appending(path: "link")
        FileManager.default.createFile(atPath: real.path, contents: Data())
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        #expect(PocketServer.shouldStop(pid: 1, pathOfPid: { _ in real.resolvingSymlinksInPath().path }, expectedBinary: link))
    }

    @Test func thePidFileIsWrittenReadAndGone() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let file = PocketServer.pidFile(model: "english", in: home)
        #expect(file.lastPathComponent == "serve-english.pid")
        #expect(PocketServer.readPid(from: file) == nil)
        try PocketServer.write(pid: 1234, to: file)
        #expect(PocketServer.readPid(from: file) == 1234)
        try FileManager.default.removeItem(at: file)
        #expect(PocketServer.readPid(from: file) == nil)
    }

    @Test func thisProcessHasAPathAndAnImpossiblePidHasNone() {
        #expect(PocketServer.executablePath(of: getpid()) != nil)
        #expect(PocketServer.executablePath(of: 999_999) == nil)
    }
}
