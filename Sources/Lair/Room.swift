import Foundation
import LairCore
import LairVoice
import Observation
import os

/// One agent you can call; while in a call it holds a live session.
@Observable @MainActor final class Call: @MainActor Identifiable {
    enum State {
        case offline, ready, listening, thinking, speaking
        /// Paused on an approval only you can give.
        case waiting
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
    var pendingApproval: ApprovalRequest?
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
    @ObservationIgnored private let notifier = ApprovalNotifier()

    /// Shortest press that counts as speech, in 16 kHz samples.
    private let minimumSpeech = 16_000 / 3

    init(config: LairConfig) {
        calls = config.agents.map(Call.init)
        focusedID = config.agents.first?.id ?? ""
    }

    var focused: Call? { calls.first { $0.id == focusedID } }

    func start() async {
        notifier.onAnswer = { [weak self] id, allow in
            guard let call = self?.calls.first(where: { $0.pendingApproval?.id == id }) else { return }
            self?.answer(call, allow: allow)
        }
        await notifier.setUp()
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
            return try ClaudeCodeSession(model: agent.model, directory: agent.directoryURL, environment: environment,
                                         permissionMode: agent.permissionMode)
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
        if call.pendingApproval != nil { answer(call, allow: false) }
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
        guard call.state == .ready || call.state == .waiting else { return }
        microphone.startCapture()
        call.state = .listening
    }

    func releaseTalk() {
        guard let call = focused, call.state == .listening else { return }
        let samples = (try? microphone.stopCapture()) ?? []
        let idle: Call.State = call.pendingApproval == nil ? .ready : .waiting
        guard samples.count >= minimumSpeech else {
            call.state = idle
            return
        }
        call.state = .thinking
        if call.pendingApproval != nil {
            Task { await hearAnswer(in: call, from: samples) }
        } else {
            call.turn = Task { await reply(in: call, to: samples) }
        }
    }

    /// The first answer wins, whether it comes by voice, the panel or the notification.
    func answer(_ call: Call, allow: Bool) {
        guard let request = call.pendingApproval else { return }
        call.pendingApproval = nil
        notifier.remove(request.id)
        call.lines.append(.init(role: .notice, text: "\(allow ? "Allowed" : "Denied"): \(request.summary)"))
        do {
            try call.session?.answer(request, allow: allow)
            if call.state == .waiting { call.state = .thinking }
        } catch {
            call.lines.append(.init(role: .notice, text: error.localizedDescription))
        }
    }

    private func hearAnswer(in call: Call, from samples: [Float]) async {
        let heard = (try? await voice.transcribe(samples)) ?? ""
        guard call.pendingApproval != nil else { return }
        if let allow = SpokenAnswer.parse(heard) {
            answer(call, allow: allow)
        } else {
            _ = try? await say("Sorry, say yes or no.", in: call)
            call.state = .waiting
        }
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

            // Text after an approval starts a new line, so the transcript reads in order.
            var answer: Int?
            var answered = false
            var splitter = SentenceSplitter()
            for try await reply in try session.ask(prompt) {
                guard !Task.isCancelled else { return }
                switch reply {
                case .text(let delta):
                    if firstToken == nil { firstToken = clock.now - start }
                    if answer == nil {
                        call.lines.append(.init(role: .agent, text: ""))
                        answer = call.lines.count - 1
                    }
                    call.lines[answer!].text += delta
                    answered = true
                    for sentence in splitter.feed(delta) where try await say(sentence, in: call) && firstAudio == nil {
                        firstAudio = clock.now - start
                    }
                case .approval(let request):
                    if let rest = splitter.flush() { _ = try await say(rest, in: call) }
                    answer = nil
                    try await ask(call, to: request)
                }
            }
            if let rest = splitter.flush(), try await say(rest, in: call), firstAudio == nil {
                firstAudio = clock.now - start
            }
            if !answered {
                call.lines.append(.init(role: .notice, text: "\(call.agent.name) didn't answer."))
            }
            await speaker.waitUntilDone()
        } catch {
            call.lines.append(.init(role: .notice, text: error.localizedDescription))
        }
    }

    /// Puts the request in front of you three ways at once; the turn stays paused until `answer`.
    private func ask(_ call: Call, to request: ApprovalRequest) async throws {
        call.pendingApproval = request
        notifier.post(request, from: call.agent.name)
        _ = try await say("\(call.agent.name) needs your OK to \(request.summary.lowercasedFirst). Allow it?", in: call)
        if call.pendingApproval?.id == request.id { call.state = .waiting }
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

private extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
