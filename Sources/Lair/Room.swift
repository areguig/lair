import Foundation
import LairCore
import LairVoice
import Observation
import os

/// One agent you can call; while in a call it holds a live session.
@Observable @MainActor final class Call: @MainActor Identifiable {
    enum State {
        case offline, ready, listening, thinking, speaking
    }

    struct Line: Identifiable {
        enum Role { case you, agent, notice }
        let id = UUID()
        let role: Role
        var text: String
    }

    let agent: AgentConfig
    var state = State.offline
    var lines: [Line] = []
    @ObservationIgnored var session: (any AgentSession)?
    @ObservationIgnored var turn: Task<Void, Never>?

    init(agent: AgentConfig) {
        self.agent = agent
    }

    var id: String { agent.id }
    var inCall: Bool { state != .offline }
}

/// The agents, the shared voice models, and push-to-talk routed to the focused agent.
@Observable @MainActor final class Room {
    enum Readiness: Equatable {
        case loading, ready, failed(String)
    }

    var readiness = Readiness.loading
    let calls: [Call]
    var focusedID: String

    @ObservationIgnored private let voice = VoiceModels()
    @ObservationIgnored let microphone = Microphone()
    @ObservationIgnored private(set) var speaker: Speaker?
    @ObservationIgnored private var environment: [String: String]?

    /// Shortest press that counts as speech, in 16 kHz samples.
    private let minimumSpeech = 16_000 / 3

    init(config: LairConfig) {
        calls = config.agents.map(Call.init)
        focusedID = config.agents.first?.id ?? ""
    }

    var focused: Call? { calls.first { $0.id == focusedID } }

    func start() async {
        environment = await LoginShell.environment()
        guard await Microphone.requestAccess() else {
            readiness = .failed("Lair needs the microphone. Allow it in System Settings › Privacy & Security.")
            return
        }
        do {
            try await voice.load(warmUpVoice: calls.first?.agent.voice ?? "af_heart")
            speaker = try Speaker()
            readiness = .ready
        } catch {
            readiness = .failed("Couldn't load the voice models: \(error.localizedDescription)")
        }
    }

    func toggle(_ call: Call) {
        focusedID = call.id
        if call.inCall { hangUp(call) } else { summon(call) }
    }

    func summon(_ call: Call) {
        guard readiness == .ready, !call.inCall else { return }
        do {
            try microphone.open()
            call.session = try session(for: call.agent)
            call.lines = []
            call.state = .ready
        } catch {
            call.lines.append(.init(role: .notice, text: "Couldn't start \(call.agent.name): \(error.localizedDescription)"))
        }
    }

    private func session(for agent: AgentConfig) throws -> any AgentSession {
        switch agent.kind {
        case .claudeCode:
            return try ClaudeCodeSession(model: agent.model, directory: agent.directoryURL, environment: environment)
        case .hermes:
            guard let url = agent.url.flatMap(URL.init(string:)) else { throw SetupError.missingURL(agent.name) }
            let secret = { Keychain.password(service: agent.keychainService, account: $0) }
            guard let apiKey = secret("api-key") else { throw SetupError.missingKey(agent.keychainService) }
            return HermesSession(baseURL: url, credentials: .init(apiKey: apiKey,
                                                                  accessClientID: secret("cf-access-client-id"),
                                                                  accessClientSecret: secret("cf-access-client-secret")),
                                 model: agent.model)
        }
    }

    enum SetupError: LocalizedError {
        case missingURL(String)
        case missingKey(String)

        var errorDescription: String? {
            switch self {
            case .missingURL(let name): "\(name) has no url in the config."
            case .missingKey(let service): "No API key in the keychain under \"\(service)\" (account \"api-key\")."
            }
        }
    }

    func hangUp(_ call: Call) {
        call.turn?.cancel()
        call.session?.stop()
        call.session = nil
        call.state = .offline
        speaker?.stop()
        if !calls.contains(where: \.inCall) { microphone.close() }
    }

    func pressTalk() {
        guard let call = focused else { return }
        if !call.inCall { summon(call) }
        guard call.state == .ready else { return }
        microphone.startCapture()
        call.state = .listening
    }

    func releaseTalk() {
        guard let call = focused, call.state == .listening else { return }
        let samples = (try? microphone.stopCapture()) ?? []
        guard samples.count >= minimumSpeech else {
            call.state = .ready
            return
        }
        call.state = .thinking
        call.turn = Task { await reply(in: call, to: samples) }
    }

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "lair", category: "turn")

    private func reply(in call: Call, to samples: [Float]) async {
        defer { if call.inCall { call.state = .ready } }
        let clock = ContinuousClock()
        let start = clock.now
        var heard, firstToken, firstAudio: Duration?
        defer {
            func ms(_ d: Duration?) -> Int { d.map { Int($0 / .milliseconds(1)) } ?? -1 }
            Self.log.info("""
                \(call.id, privacy: .public): \(samples.count / 16) ms of speech; heard \(ms(heard)) ms, \
                first token \(ms(firstToken)) ms, first audio \(ms(firstAudio)) ms after release
                """)
        }
        do {
            let prompt = try await voice.transcribe(samples)
            heard = clock.now - start
            guard !prompt.isEmpty, let session = call.session, let speaker else { return }
            call.lines.append(.init(role: .you, text: prompt))
            call.lines.append(.init(role: .agent, text: ""))
            let answer = call.lines.count - 1

            var splitter = SentenceSplitter()
            for try await delta in try session.ask(prompt) {
                guard !Task.isCancelled else { return }
                if firstToken == nil { firstToken = clock.now - start }
                call.lines[answer].text += delta
                for sentence in splitter.feed(delta) where try await say(sentence, in: call) && firstAudio == nil {
                    firstAudio = clock.now - start
                }
            }
            if let rest = splitter.flush(), try await say(rest, in: call), firstAudio == nil {
                firstAudio = clock.now - start
            }
            if call.lines[answer].text.isEmpty {
                call.lines[answer] = .init(role: .notice, text: "\(call.agent.name) didn't answer.")
            }
            await speaker.waitUntilDone()
        } catch {
            call.lines.append(.init(role: .notice, text: error.localizedDescription))
        }
    }

    /// Returns whether the sentence was queued for playback.
    private func say(_ sentence: String, in call: Call) async throws -> Bool {
        let text = Speakable.text(sentence)
        guard !text.isEmpty, let speaker else { return false }
        let samples = try await voice.speech(for: text, voice: call.agent.voice)
        guard !Task.isCancelled else { return false }
        speaker.enqueue(samples)
        call.state = .speaking
        return true
    }
}
