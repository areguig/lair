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
    /// Finished or needs you while you were talking to someone else.
    var unread = false
    @ObservationIgnored var session: (any AgentSession)?
    @ObservationIgnored var turn: Task<Void, Never>?
    /// Identifies the running turn, so an interrupted one can't reset the state of the next.
    @ObservationIgnored var turnID: UUID?

    init(agent: AgentConfig) {
        self.agent = agent
    }

    var id: String { agent.id }
    var inCall: Bool { state != .offline }
}

/// The agents, the shared voice models, and push-to-talk routed to the focused agent.
/// Only the focused agent speaks; the others work silently and announce themselves in one line.
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
        notifier.onAnswer = { [weak self] id, decision in
            guard let call = self?.calls.first(where: { $0.pendingApproval?.id == id }) else { return }
            self?.answer(call, decision: decision)
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
        focus(call)
        if call.inCall { hangUp(call) } else { summon(call) }
    }

    /// Hands the floor to `call`; the agent that was speaking goes on working silently.
    func focus(_ call: Call) {
        call.unread = false
        guard call.id != focusedID else { return }
        if let previous = focused {
            if previous.state == .listening {
                _ = try? microphone.stopCapture()
                previous.state = previous.pendingApproval == nil ? .ready : .waiting
            }
            if previous.state == .speaking {
                speaker?.stop()
                previous.state = .thinking
            }
        }
        focusedID = call.id
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
                                         permissionMode: agent.permissionMode, errorLog: AgentLog.url(for: agent.id))
        case .omp:
            return try OmpSession(model: agent.model, directory: agent.directoryURL, environment: environment,
                                  errorLog: AgentLog.url(for: agent.id))
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
        if call.pendingApproval != nil { answer(call, decision: .deny) }
        call.turn?.cancel()
        call.session?.stop()
        call.session = nil
        if call.state == .speaking { speaker?.stop() }
        call.state = .offline
        call.unread = false
        if !calls.contains(where: \.inCall) { microphone.close() }
    }

    func pressTalk() {
        guard let call = focused else { return }
        if !call.inCall { summon(call) }
        // Talking over the agent cuts it off.
        if call.pendingApproval == nil, call.state == .speaking || call.state == .thinking { interrupt(call) }
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

    func interrupt(_ call: Call) {
        if call.id == focusedID { speaker?.stop() }
        call.turnID = nil
        call.turn?.cancel()
        call.session?.interrupt()
        call.state = .ready
    }

    /// The first answer wins, whether it comes by voice, the panel or the notification.
    func answer(_ call: Call, decision: ApprovalDecision) {
        guard let request = call.pendingApproval else { return }
        call.pendingApproval = nil
        notifier.remove(request.id)
        let decision = decision == .allowAlways && !request.canAlwaysAllow ? .allowOnce : decision
        let verdict = switch decision {
        case .allowOnce: "Allowed once"
        case .allowAlways: "Always allowed"
        case .deny: "Denied"
        }
        call.lines.append(.init(role: .notice, text: "\(verdict): \(request.summary)"))
        do {
            try call.session?.answer(request, decision: decision)
            if call.state == .waiting { call.state = .thinking }
        } catch {
            call.lines.append(.init(role: .notice, text: error.localizedDescription))
        }
    }

    private func hearAnswer(in call: Call, from samples: [Float]) async {
        let heard = (try? await voice.transcribe(samples)) ?? ""
        guard call.pendingApproval != nil else { return }
        if let decision = SpokenAnswer.parse(heard) {
            answer(call, decision: decision)
        } else {
            _ = try? await say("Sorry, say" + (call.pendingApproval?.canAlwaysAllow == true ? " yes, always, or no." : " yes or no."), in: call)
            call.state = .waiting
        }
    }

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "lair", category: "turn")

    private static let clock = ContinuousClock()

    private func reply(in call: Call, to samples: [Float]) async {
        let start = Self.clock.now
        let prompt: String
        do {
            prompt = try await voice.transcribe(samples)
        } catch {
            call.lines.append(.init(role: .notice, text: error.localizedDescription))
            call.state = .ready
            return
        }
        guard !Task.isCancelled else { return }
        guard !prompt.isEmpty else {
            call.state = .ready
            return
        }
        // "Sage, …" while talking to Claude goes to Sage.
        let others = calls.filter { $0.id != call.id }
        if let (name, rest) = Addressing.split(prompt, names: others.map(\.agent.name)),
           let target = others.first(where: { $0.agent.name == name }) {
            call.state = .ready
            focus(target)
            if !target.inCall { summon(target) }
            guard target.state == .ready else {
                target.lines.append(.init(role: .notice, text: "\(name) is busy; try again when it's done."))
                return
            }
            target.state = .thinking
            target.turn = Task { await converse(in: target, prompt: rest, speech: samples.count, start: start) }
            return
        }
        await converse(in: call, prompt: prompt, speech: samples.count, start: start)
    }

    private func converse(in call: Call, prompt: String, speech: Int, start: ContinuousClock.Instant) async {
        let turnID = UUID()
        call.turnID = turnID
        defer { if call.inCall, call.turnID == turnID { call.state = .ready } }
        let clock = Self.clock
        let heard: Duration? = clock.now - start
        var firstToken, firstAudio: Duration?
        defer {
            func ms(_ d: Duration?) -> Int { d.map { Int($0 / .milliseconds(1)) } ?? -1 }
            Self.log.info("""
                \(call.id, privacy: .public): \(speech / 16) ms of speech; heard \(ms(heard)) ms, \
                first token \(ms(firstToken)) ms, first audio \(ms(firstAudio)) ms after release
                """)
        }
        do {
            guard let session = call.session, let speaker else { return }
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
            if call.id == focusedID {
                await speaker.waitUntilDone()
            } else if !Task.isCancelled {
                call.unread = true
                announce("\(call.agent.name) is done.", for: call)
            }
        } catch {
            guard !Task.isCancelled else { return }
            if error is AgentStopped {
                let reason = AgentLog.firstLine(for: call.id).map { ": \($0)" } ?? "."
                call.lines.append(.init(role: .notice, text: "\(call.agent.name) stopped\(reason) "
                    + "Full log in Library/Logs/Lair/\(call.id).log."))
                hangUp(call)
            } else {
                call.lines.append(.init(role: .notice, text: error.localizedDescription))
            }
        }
    }

    /// Puts the request in front of you three ways at once; the turn stays paused until `answer`.
    private func ask(_ call: Call, to request: ApprovalRequest) async throws {
        call.pendingApproval = request
        notifier.post(request, from: call.agent.name)
        if call.id != focusedID {
            call.unread = true
            call.state = .waiting
            announce("\(call.agent.name) needs your OK.", for: call)
            return
        }
        _ = try await say("\(call.agent.name) needs your OK to \(request.summary.lowercasedFirst). Allow it?" + (request.canAlwaysAllow ? " Say yes, always, or no." : " Say yes or no."), in: call)
        if call.pendingApproval?.id == request.id { call.state = .waiting }
    }

    /// One line from a background agent, once the focused one has stopped talking.
    private func announce(_ text: String, for call: Call) {
        Task {
            while let current = focused, current.state == .speaking || current.state == .listening {
                try? await Task.sleep(for: .milliseconds(300))
            }
            guard let speaker, let samples = try? await voice.speech(for: text, voice: call.agent.voice) else { return }
            speaker.enqueue(samples)
        }
    }

    /// Returns whether the sentence was queued for playback; only the focused agent is heard.
    private func say(_ sentence: String, in call: Call) async throws -> Bool {
        let text = Speakable.text(sentence)
        guard !text.isEmpty, call.id == focusedID, let speaker else { return false }
        let samples = try await voice.speech(for: text, voice: call.agent.voice)
        // Focus may have moved while the sentence was being synthesized.
        guard !Task.isCancelled, call.id == focusedID else { return false }
        speaker.enqueue(samples)
        call.state = .speaking
        return true
    }
}

private extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
