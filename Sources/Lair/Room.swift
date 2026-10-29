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
        /// `info` is what Lair tells you along the way; `problem` is something that went wrong.
        enum Role { case you, agent, info, problem }
        /// A button next to a line, so a problem comes with its way out.
        enum Action: Equatable { case openSettings, showLog(agentID: String) }
        let id = UUID()
        let role: Role
        var text: String
        var action: Action?
        /// Links, paths and commands the agent showed instead of saying (`<show>…</show>`).
        var shown: [String] = []
    }

    var agent: AgentConfig
    var state = State.offline
    var lines: [Line] = []
    var pendingApproval: ApprovalRequest?
    /// Finished or needs you while you were talking to someone else.
    var unread = false
    /// Model and thinking level, once the agent says.
    var details: String?
    /// Models the agent offers on this call, once it lists them.
    var models: [String] = []
    /// The thinking level this call runs at, as last set.
    var thinking: String?
    /// A thinking level asked for mid-call that the agent can only take from its next call.
    @ObservationIgnored var thinkingNextCall: String?
    /// What the agent said while another agent had the floor, heard when you switch to it.
    @ObservationIgnored var unheard: [String] = []
    /// The whole exchange for Mission Control; kept across calls with this agent until Lair quits.
    var entries: [LogEntry] = []
    @ObservationIgnored var session: (any AgentSession)?
    @ObservationIgnored var turn: Task<Void, Never>?
    /// Identifies the running turn, so an interrupted one can't reset the state of the next.
    @ObservationIgnored var turnID: UUID?
    /// Background work finished while a turn was running; heard once that turn ends.
    @ObservationIgnored var newsWaiting = false
    /// What other agents answered for this one while you talked to them; sent before its next turn.
    @ObservationIgnored var context: [String] = []

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
        case loading, ready, microphoneDenied, failed(String)
    }

    var readiness = Readiness.loading
    /// Models each agent offered on its last call, offered again in Settings.
    private(set) var knownModels: [String: [String]] = [:]
    /// A short-lived line under the agent's name, for a key press that can't do anything yet.
    private(set) var hint: String?
    private(set) var calls: [Call]
    var focusedID: String
    /// Listening for your reply on its own, after the agent spoke.
    struct Answering: Equatable {
        let callID: String
        let since: Date
        /// You've started talking, so the wait is over.
        var hearing = false
    }

    /// Settable so snapshots can stage it.
    var answering: Answering?
    /// Off in General settings: you always press the key.
    @ObservationIgnored private var listensForAnswers: Bool

    @ObservationIgnored private let voice = VoiceModels()
    @ObservationIgnored let microphone = Microphone()
    @ObservationIgnored private(set) var speaker: Speaker?
    /// Drives the orb instead of the live microphone and speaker, for the demo video.
    @ObservationIgnored var meterOverride: LevelMeter?
    @ObservationIgnored private var environment: [String: String]?
    @ObservationIgnored private let notifier = ApprovalNotifier()
    @ObservationIgnored private var hintTask: Task<Void, Never>?

    /// Shortest press that counts as speech, in 16 kHz samples.
    private let minimumSpeech = 16_000 / 3

    init(config: LairConfig) {
        calls = config.enabledAgents.map(Call.init)
        focusedID = config.enabledAgents.first?.id ?? ""
        listensForAnswers = config.listensForAnswers
    }

    var focused: Call? { calls.first { $0.id == focusedID } }

    /// Takes a new config without dropping calls: an agent in a call keeps it, and its model, folder or address
    /// apply from its next call; removed or turned-off agents are hung up.
    func apply(_ config: LairConfig) {
        let next = config.enabledAgents.map { agent in
            guard let call = calls.first(where: { $0.id == agent.id }) else { return Call(agent: agent) }
            call.agent = agent
            return call
        }
        for call in calls where !next.contains(where: { $0 === call }) && call.inCall { hangUp(call) }
        calls = next
        if focused == nil { focusedID = calls.first?.id ?? "" }
        listensForAnswers = config.listensForAnswers
    }

    /// Says a short line in `voice`, so a voice can be tried before choosing it.
    func preview(voice: String, name: String) {
        guard readiness == .ready, let speaker else { return }
        Task {
            guard let samples = try? await self.voice.speech(for: "Hi, I'm \(name).", voice: voice) else { return }
            speaker.enqueue(samples)
        }
    }

    func start() async {
        notifier.onAnswer = { [weak self] id, decision in
            guard let call = self?.calls.first(where: { $0.pendingApproval?.id == id }) else { return }
            self?.answer(call, decision: decision)
        }
        notifier.onOpen = { [weak self] id in
            guard let call = self?.calls.first(where: { $0.pendingApproval?.id == id }) else { return }
            self?.focus(call)
        }
        await notifier.setUp()
        environment = await LoginShell.environment()
        await prepare()
    }

    /// Microphone access and the voice models; run again by "Try again" after a failure.
    func prepare() async {
        readiness = .loading
        guard await Microphone.requestAccess() else {
            readiness = .microphoneDenied
            return
        }
        do {
            try await voice.load(warmUpVoice: calls.first?.agent.voice ?? "af_heart")
            if speaker == nil { speaker = try Speaker() }
            readiness = .ready
        } catch {
            readiness = .failed("Couldn't load the voices: \(error.localizedDescription)")
        }
    }

    private func show(hint text: String) {
        hint = text
        hintTask?.cancel()
        hintTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            if !Task.isCancelled { hint = nil }
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
        defer { replayUnheard(call) }
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
        // A new attempt replaces the last setup problem instead of stacking another.
        call.lines.removeAll { $0.action == .openSettings }
        do {
            try microphone.open()
            call.thinking = call.thinkingNextCall ?? call.agent.thinking
            let session = try session(for: call.agent, thinking: call.thinking)
            Self.log.notice("""
                \(call.id, privacy: .public): call started, \(call.agent.kind.rawValue, privacy: .public) \
                model \(call.agent.model ?? "default", privacy: .public)
                """)
            call.thinkingNextCall = nil
            call.session = session
            call.details = nil
            call.models = []
            Task {
                for await models in session.models where !models.isEmpty {
                    call.models = models
                    knownModels[call.id] = models
                }
            }
            Task { for await details in session.details { call.details = details } }
            Task { for await _ in session.news { hearNews(from: call) } }
            call.lines = []
            call.state = .ready
        } catch let error as SetupError {
            report(in: call, .init(role: .problem, text: error.message(for: call.agent.name), action: .openSettings))
        } catch {
            report(in: call, .init(role: .problem, text: "Couldn't start \(call.agent.name): \(error.localizedDescription)",
                                    action: .openSettings))
        }
    }

    private func session(for agent: AgentConfig, thinking: String?) throws -> any AgentSession {
        switch agent.kind {
        case .claudeCode:
            return try ClaudeCodeSession(model: agent.model, effort: thinking, directory: agent.directoryURL,
                                         environment: environment,
                                         permissionMode: agent.permissionMode, errorLog: AgentLog.url(for: agent.id),
                                         systemPrompt: callPrompt(for: agent))
        case .omp:
            return try OmpSession(model: agent.model, thinking: thinking, directory: agent.directoryURL,
                                  environment: environment,
                                  errorLog: AgentLog.url(for: agent.id), systemPrompt: callPrompt(for: agent))
        case .hermes:
            guard let url = agent.url.flatMap(URL.init(string:)), url.host() != nil else { throw SetupError.missingAddress }
            let secret = { Keychain.password(service: agent.keychainService, account: $0) }
            guard let apiKey = secret("api-key") else { throw SetupError.missingKey }
            var headers: [String: String] = [:]
            for name in agent.headers ?? [] { headers[name] = secret(AgentConfig.headerAccount(name)) }
            return HermesSession(baseURL: url, credentials: .init(apiKey: apiKey, headers: headers), model: agent.model)
        }
    }

    /// A problem line, with its sound so it's noticed with the panel closed.
    private func report(in call: Call, _ line: Call.Line) {
        Self.log.error("\(call.id, privacy: .public): \(line.text, privacy: .public)")
        call.lines.append(line)
        call.log(.problem(line.text))
        speaker?.play(.problem)
    }

    /// Hermes agents keep the identity they already have; local agents get their name and soul.
    private func callPrompt(for agent: AgentConfig) -> String {
        VoicePrompt.forCall(name: agent.name, soul: Souls.standard.soul(for: agent.id))
    }

    enum SetupError: Error {
        case missingAddress, missingKey

        func message(for name: String) -> String {
            switch self {
            case .missingAddress: "\(name) needs an address. Add it in Settings › Agents."
            case .missingKey: "\(name) needs an API key. Add it in Settings › Agents."
            }
        }
    }

    func hangUp(_ call: Call) {
        if call.pendingApproval != nil { answer(call, decision: .deny) }
        call.context = []
        call.turn?.cancel()
        call.session?.stop()
        call.session = nil
        if call.state == .speaking { speaker?.stop() }
        call.state = .offline
        call.unread = false
        call.unheard = []
        if !calls.contains(where: \.inCall) { microphone.close() }
    }

    func pressTalk() {
        switch readiness {
        case .ready: break
        case .loading: return show(hint: "Still getting the voices ready…")
        case .microphoneDenied, .failed: return show(hint: "Lair can't listen yet; see below.")
        }
        // Already listening for your answer: the key takes over, and letting go sends.
        if answering != nil, focused?.state == .listening { return answering = nil }
        // An agent waiting on your OK takes the answer, even if another one is in focus.
        if focused?.state != .waiting, let waiting = calls.first(where: { $0.state == .waiting }) { focus(waiting) }
        guard let call = focused else { return show(hint: "Add an agent in Settings first.") }
        if !call.inCall { summon(call) }
        // Talking over the agent cuts it off.
        if call.pendingApproval == nil, call.state == .speaking || call.state == .thinking {
            interrupt(call)
            call.lines.append(.init(role: .info, text: "You cut in."))
        }
        guard call.state == .ready || call.state == .waiting else { return }
        speaker?.play(.listening)
        microphone.startCapture()
        call.state = .listening
    }

    /// A click instead of a held key: the first starts listening, the next sends.
    func toggleTalk() {
        if focused?.state == .listening { releaseTalk() } else { pressTalk() }
    }

    func releaseTalk() {
        guard let call = focused, call.state == .listening else { return }
        answering = nil
        let samples = (try? microphone.stopCapture()) ?? []
        let idle: Call.State = call.pendingApproval == nil ? .ready : .waiting
        guard samples.count >= minimumSpeech else {
            call.state = idle
            return
        }
        call.state = .thinking
        speaker?.play(.sent)
        if call.pendingApproval != nil {
            Task { await hearAnswer(in: call, from: samples) }
        } else {
            call.turn = Task { await reply(in: call, to: samples) }
        }
    }

    /// What the orb follows: your voice while it listens, its own while it speaks.
    func meter(for call: Call) -> LevelMeter? {
        switch call.state {
        case .listening: meterOverride ?? microphone.meter
        case .speaking: meterOverride ?? speaker?.meter
        default: nil
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
        call.lines.append(.init(role: .info, text: "\(verdict): \(request.summary)"))
        call.log(.note("\(verdict): \(request.summary)"))
        do {
            try call.session?.answer(request, decision: decision)
            if call.state == .waiting { call.state = .thinking }
        } catch {
            report(in: call, .init(role: .problem, text: error.localizedDescription))
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
            await speaker?.waitUntilDone()
            if call.pendingApproval != nil { listenForAnswer(in: call) }
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
            report(in: call, .init(role: .problem, text: "Couldn't make out what you said: \(error.localizedDescription)"))
            call.state = .ready
            return
        }
        guard !Task.isCancelled else { return }
        guard !prompt.isEmpty else {
            call.state = .ready
            return
        }
        if pass(prompt, from: call, speech: samples.count, start: start) { return }
        // "Echo, …" while talking to Claude goes to Echo.
        let others = calls.filter { $0.id != call.id }
        if let (name, rest) = Addressing.split(prompt, names: others.map(\.agent.name)),
           let target = others.first(where: { $0.agent.name == name }) {
            call.state = .ready
            focus(target)
            if !target.inCall { summon(target) }
            guard target.inCall else { return }
            guard target.state == .ready else {
                target.lines.append(.init(role: .info, text: "\(name) is busy; say it again when it's done."))
                return
            }
            target.state = .thinking
            target.turn = Task { await converse(in: target, prompt: rest, speech: samples.count, start: start) }
            return
        }
        // "Switch to Opus", "think harder": for Lair, not for the agent.
        if let command = VoiceCommand.parse(prompt) {
            call.lines.append(.init(role: .you, text: prompt))
            await run(command, in: call)
            if call.inCall { call.state = .ready }
            return
        }
        await converse(in: call, prompt: prompt, speech: samples.count, start: start)
    }

    /// Text typed in Mission Control: the same as saying it, without the microphone.
    func type(_ text: String, to call: Call) {
        guard readiness == .ready else { return show(hint: "Still getting the voices ready…") }
        focus(call)
        if !call.inCall { summon(call) }
        if let request = call.pendingApproval {
            guard let decision = SpokenAnswer.parse(text) else {
                return show(hint: "Type yes" + (request.canAlwaysAllow ? ", always" : "") + " or no, or use the buttons.")
            }
            return answer(call, decision: decision)
        }
        if call.state == .speaking || call.state == .thinking { interrupt(call) }
        guard call.state == .ready else { return }
        if pass(text, from: call, speech: 0, start: Self.clock.now) { return }
        if let command = VoiceCommand.parse(text) {
            call.lines.append(.init(role: .you, text: text))
            call.log(.you(text))
            Task { await run(command, in: call) }
            return
        }
        call.state = .thinking
        call.turn = Task { await converse(in: call, prompt: text, speech: 0, start: Self.clock.now) }
    }

    /// "Ask Echo to check it", or "Nova, ask Claude what it thinks": the target answers, with the source's latest
    /// exchange as context, and the source hears what it said on its next turn. Returns whether `text` was one.
    private func pass(_ text: String, from heard: Call, speech: Int, start: ContinuousClock.Instant) -> Bool {
        guard let relay = Relay.parse(text, names: calls.map(\.agent.name)),
              let source = relay.source.map(call(named:)) ?? heard, let target = call(named: relay.target),
              source !== target
        else { return false }
        if heard.state == .thinking { heard.state = .ready }
        let asked = source.lines.last { $0.role == .you }?.text
        let answered = source.lines.last { $0.role == .agent && !$0.text.isEmpty }?.text
        source.lines.append(.init(role: .info, text: "Passed on to \(target.agent.name)."))
        source.log(.note("Passed on to \(target.agent.name): \(relay.words)"))
        focus(target)
        if !target.inCall { summon(target) }
        guard target.inCall else { return true }
        guard target.state == .ready else {
            target.lines.append(.init(role: .info, text: "\(target.agent.name) is busy; say it again when it's done."))
            return true
        }
        let from = answered == nil ? "From \(source.agent.name)" : "From \(source.agent.name), with its last answer"
        target.lines.append(.init(role: .info, text: from))
        target.log(.note(from))
        // Heard in the source's voice, so the hand-off isn't a silence.
        if speech > 0 { announce("Asking \(target.agent.name).", for: source) }
        target.state = .thinking
        let prompt = VoicePrompt.relay(relay.words, from: source.agent.name, asked: asked, answered: answered)
        let before = target.lines.count
        target.turn = Task {
            await converse(in: target, prompt: prompt, speech: speech, start: start,
                           shown: .init(role: .you, text: relay.words))
            guard source.inCall, let answer = target.lines.dropFirst(before)
                .last(where: { $0.role == .agent && !$0.text.isEmpty })?.text else { return }
            source.context.append(VoicePrompt.relayed(relay.words, to: target.agent.name, answer: answer))
        }
        return true
    }

    private func call(named name: String) -> Call? {
        calls.first { $0.agent.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Changes the call's model or thinking level, from a voice command or the panel, and says what happened.
    func run(_ command: VoiceCommand, in call: Call) async {
        guard let session = call.session else { return }
        let local = call.agent.kind != .hermes
        let confirmation: String
        do {
            switch command {
            case .model(let model):
                try session.setModel(model)
                confirmation = "Switched to \(model)."
            case .thinking(let level):
                confirmation = try setThinking(level, in: call, session: session)
            case .thinkMore, .thinkLess:
                guard let level = step(command == .thinkMore ? 1 : -1, from: call.thinking, in: session.thinkingLevels)
                else { throw ChangeLater() }
                confirmation = try setThinking(level, in: call, session: session)
            case .fast where call.agent.kind == .claudeCode:
                try session.setModel("haiku")
                confirmation = "Going fast, on Haiku."
            case .deep where call.agent.kind == .claudeCode:
                try session.setModel("opus")
                confirmation = "Going deep, on Opus."
            case .fast, .deep:
                guard local else { throw ChangeLater() }
                confirmation = try setThinking(command == .fast ? "low" : "high", in: call, session: session)
            }
        } catch is ChangeLater {
            confirmation = local ? "That can't change during a call." : "\(call.agent.name) chooses that itself."
        } catch {
            report(in: call, .init(role: .problem, text: error.localizedDescription))
            return
        }
        call.lines.append(.init(role: .info, text: confirmation))
        _ = try? await say(confirmation, in: call)
    }

    /// Thinking changes now when the agent allows it, otherwise from the next call.
    private func setThinking(_ level: String, in call: Call, session: any AgentSession) throws -> String {
        guard session.thinkingLevels.isEmpty || session.thinkingLevels.contains(level) else {
            throw AgentFailure(message: "\(call.agent.name) has no \(level) thinking level.")
        }
        do {
            try session.setThinking(level)
            call.thinking = level
            return "Thinking \(level) now."
        } catch is ChangeLater where !session.thinkingLevels.isEmpty {
            call.thinkingNextCall = level
            return "I'll think \(level) from the next call."
        }
    }

    private func step(_ by: Int, from current: String?, in levels: [String]) -> String? {
        guard !levels.isEmpty else { return nil }
        let index = current.flatMap { levels.firstIndex(of: $0) } ?? levels.firstIndex(of: "medium") ?? levels.count / 2
        return levels[min(max(index + by, 0), levels.count - 1)]
    }

    /// The agent finished work in the background: take a turn so it says what it found.
    private func hearNews(from call: Call) {
        guard call.inCall, call.session != nil else { return }
        guard call.state == .ready, call.pendingApproval == nil else {
            call.newsWaiting = true
            return
        }
        call.newsWaiting = false
        call.state = .thinking
        call.turn = Task {
            await converse(in: call, prompt: VoicePrompt.backgroundResult, speech: 0, start: Self.clock.now,
                           shown: .init(role: .info, text: "Background task finished"))
        }
    }

    /// `shown` replaces the prompt in the transcript when the prompt isn't something you said.
    private func converse(in call: Call, prompt: String, speech: Int, start: ContinuousClock.Instant,
                          shown: Call.Line? = nil) async {
        let turnID = UUID()
        call.turnID = turnID
        call.unheard = []
        // The agent answered what you said aloud: listen a few seconds for your reply. Typed turns don't open the mic.
        var listenAfter = false
        defer {
            if call.inCall, call.turnID == turnID {
                call.state = .ready
                if call.newsWaiting { hearNews(from: call) } else if listenAfter { listenForAnswer(in: call) }
            }
        }
        let clock = Self.clock
        let heard: Duration? = clock.now - start
        var firstToken, firstAudio: Duration?
        defer {
            func ms(_ d: Duration?) -> Int { d.map { Int($0 / .milliseconds(1)) } ?? -1 }
            func optionalMS(_ d: Duration?) -> Int? { d.map { Int($0 / .milliseconds(1)) } }
            call.log(.timing(heard: speech > 0 ? optionalMS(heard) : nil, firstWord: optionalMS(firstToken),
                             firstSound: optionalMS(firstAudio), total: ms(clock.now - start)))
            Self.log.notice("""
                \(call.id, privacy: .public): \(speech / 16) ms of speech; heard \(ms(heard)) ms, \
                first token \(ms(firstToken)) ms, first audio \(ms(firstAudio)) ms after release
                """)
        }
        do {
            guard let session = call.session, let speaker else { return }
            call.lines.append(shown ?? .init(role: .you, text: prompt))
            call.log(shown.map { $0.role == .you ? .you($0.text) : .note($0.text) } ?? .you(prompt))
            let sent = (call.context + [prompt]).joined(separator: "\n\n")
            call.context = []

            // Text after an approval starts a new line, so the transcript reads in order.
            var answer: Int?
            var answered = false
            var splitter = SentenceSplitter()
            // Links and paths in <show> tags go to the screen, never to the voice.
            var showing = ShowFilter()
            for try await reply in try session.ask(sent) {
                guard !Task.isCancelled else { return }
                switch reply {
                case .activity(let activity):
                    call.record(activity)
                case .text(let delta):
                    if firstToken == nil { firstToken = clock.now - start }
                    call.logText(delta)
                    if answer == nil {
                        call.lines.append(.init(role: .agent, text: ""))
                        answer = call.lines.count - 1
                    }
                    let visible = showing.feed(delta)
                    call.lines[answer!].text += visible.spoken
                    call.lines[answer!].shown += visible.shown
                    answered = true
                    for sentence in splitter.feed(visible.spoken) where try await say(sentence, in: call) && firstAudio == nil {
                        firstAudio = clock.now - start
                    }
                case .approval(let request):
                    let visible = showing.flush()
                    if let answer {
                        call.lines[answer].text += visible.spoken
                        call.lines[answer].shown += visible.shown
                    }
                    for sentence in splitter.feed(visible.spoken) { _ = try await say(sentence, in: call) }
                    if let rest = splitter.flush() { _ = try await say(rest, in: call) }
                    answer = nil
                    try await ask(call, to: request)
                }
            }
            let visible = showing.flush()
            if let answer {
                call.lines[answer].text += visible.spoken
                call.lines[answer].shown += visible.shown
            }
            for sentence in splitter.feed(visible.spoken) { _ = try await say(sentence, in: call) }
            if let rest = splitter.flush(), try await say(rest, in: call), firstAudio == nil {
                firstAudio = clock.now - start
            }
            if !answered {
                report(in: call, .init(role: .problem, text: "\(call.agent.name) didn't answer."))
            }
            if call.id == focusedID {
                await speaker.waitUntilDone()
                listenAfter = answered && speech > 0
            } else if !Task.isCancelled {
                call.unread = true
                speaker.play(.done)
                announce("\(call.agent.name) is done.", for: call)
            }
        } catch {
            guard !Task.isCancelled else { return }
            if error is AgentStopped {
                let reason = AgentLog.firstLine(for: call.id).map { ": \($0)" } ?? "."
                report(in: call, .init(role: .problem, text: "\(call.agent.name) stopped\(reason)",
                                        action: .showLog(agentID: call.id)))
                hangUp(call)
            } else {
                report(in: call, .init(role: .problem, text: error.localizedDescription))
            }
        }
    }

    /// Puts the request in front of you three ways at once; the turn stays paused until `answer`.
    private func ask(_ call: Call, to request: ApprovalRequest) async throws {
        call.pendingApproval = request
        call.log(.approval("\(request.tool): \(request.summary)"))
        notifier.post(request, from: call.agent.name)
        speaker?.play(.needsYou)
        if call.id != focusedID {
            call.unread = true
            call.state = .waiting
            announce("\(call.agent.name) needs your OK.", for: call)
            return
        }
        _ = try await say("\(call.agent.name) needs your OK to \(request.summary.lowercasedFirst). Allow it?" + (request.canAlwaysAllow ? " Say yes, always, or no." : " Say yes or no."), in: call)
        if call.pendingApproval?.id == request.id { call.state = .waiting }
        await speaker?.waitUntilDone()
        if call.pendingApproval?.id == request.id { listenForAnswer(in: call) }
    }

    /// The microphone opens on its own after the agent speaks and sends once you've answered; silence closes it.
    /// Opening only after the voice has finished keeps the agent from hearing itself.
    private func listenForAnswer(in call: Call) {
        guard listensForAnswers else { return }
        Task {
            guard var detector = await voice.detector(), readiness == .ready, call.id == focusedID,
                  call.state == .ready || call.state == .waiting, !microphone.isCapturing
            else { return }
            speaker?.play(.listening)
            microphone.startCapture()
            call.state = .listening
            answering = Answering(callID: call.id, since: .now)
            let start = Self.clock.now
            var turn = FollowUp.Turn()
            while true {
                try? await Task.sleep(for: .milliseconds(250))
                guard answering?.callID == call.id, call.state == .listening, call.id == focusedID,
                      let samples = try? microphone.captured(),
                      let next = try? await voice.listen(detector, to: samples),
                      answering?.callID == call.id, call.state == .listening
                else { break }
                detector = next
                if detector.speaking { answering?.hearing = true }
                switch turn.update(speaking: detector.speaking, elapsed: Self.clock.now - start) {
                case .listen: continue
                case .send: return releaseTalk()
                case .giveUp:
                    _ = try? microphone.stopCapture()
                    call.state = call.pendingApproval == nil ? .ready : .waiting
                }
                break
            }
            if answering?.callID == call.id { answering = nil }
        }
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
    /// Speaks what the agent said in the background, once you switch to it and it isn't mid-turn.
    private func replayUnheard(_ call: Call) {
        guard !call.unheard.isEmpty, call.state == .ready || call.state == .waiting else {
            // Mid-turn, it speaks from here on; the earlier part stays in the transcript.
            if call.inCall, call.state != .ready, call.state != .waiting { call.unheard = [] }
            return
        }
        let sentences = call.unheard
        call.unheard = []
        let resume = call.state
        Task {
            for sentence in sentences {
                guard call.id == focusedID else { return }
                _ = try? await say(sentence, in: call)
            }
            await speaker?.waitUntilDone()
            if call.id == focusedID, call.state == .speaking { call.state = resume }
            listenForAnswer(in: call)
        }
    }

    private func say(_ sentence: String, in call: Call) async throws -> Bool {
        let text = Speakable.text(sentence)
        guard !text.isEmpty, let speaker else { return false }
        guard call.id == focusedID else {
            call.unheard.append(sentence)
            return false
        }
        let samples = try await voice.speech(for: text, voice: call.agent.voice)
        // Focus may have moved while the sentence was being synthesized.
        guard !Task.isCancelled, call.id == focusedID else {
            call.unheard.append(sentence)
            return false
        }
        speaker.enqueue(samples)
        call.state = .speaking
        return true
    }
}

private extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
