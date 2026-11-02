import Foundation
import LairACP
import LairCore
import LairMCP
import LairVoice
import Observation
import os

/// The agents, the shared voice models, and push-to-talk routed to the focused agent.
/// Only the focused agent speaks; the others work silently and announce themselves in one line.
@Observable @MainActor final class Room {
    enum Readiness: Equatable {
        case loading, ready, microphoneDenied, failed(String)
    }

    var readiness = Readiness.loading
    /// Models each agent offered on its last call, offered again in Settings.
    private(set) var knownModels: [String: [String]] = [:]
    /// Thinking levels each agent offered on its last call, for Settings.
    private(set) var knownThinking: [String: [String]] = [:]
    /// The other choices each agent offered on its last call, such as how it asks for approval, for Settings.
    private(set) var knownOptions: [String: [AgentOption]] = [:]
    /// A short-lived line under the agent's name, for a key press that can't do anything yet.
    private(set) var hint: String?
    var calls: [Call]
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
    @ObservationIgnored var listensForAnswers: Bool

    @ObservationIgnored let voice = VoiceModels()
    @ObservationIgnored let microphone = Microphone()
    @ObservationIgnored private(set) var speaker: Speaker?
    /// Drives the orb instead of the live microphone and speaker, for the demo video.
    @ObservationIgnored var meterOverride: LevelMeter?
    @ObservationIgnored private var environment: [String: String]?

    /// Whether a preset's program is found on your login shell's PATH; unknown until that PATH is read.
    func isInstalled(_ preset: AgentPreset) -> Bool? {
        environment.map { preset.isInstalled(path: $0["PATH"]) }
    }
    @ObservationIgnored let notifier = ApprovalNotifier()
    @ObservationIgnored private var hintTask: Task<Void, Never>?

    /// Shortest press that counts as speech, in 16 kHz samples.
    let minimumSpeech = 16_000 / 3

    init(config: LairConfig) {
        calls = config.enabledAgents.map(Call.init)
        focusedID = config.enabledAgents.first?.id ?? ""
        listensForAnswers = config.listensForAnswers
        guestSettings = config.guests
    }

    /// Never nobody while anyone's in the room: a stale id falls back to the first call.
    var focused: Call? { calls.first { $0.id == focusedID } ?? calls.first }

    /// Takes a new config without dropping calls: an agent in a call keeps it, and its model, folder or address
    /// apply from its next call; removed or turned-off agents are hung up.
    func apply(_ config: LairConfig) {
        let next = config.enabledAgents.map { agent in
            guard let call = calls.first(where: { $0.id == agent.id }) else { return Call(agent: agent) }
            call.agent = agent
            return call
        }
        for call in calls where !call.stranger && !next.contains(where: { $0 === call }) {
            // A removed agent whose session is still connected stays, as that session.
            if let visitor = call.visitor {
                call.agent.kind = .guest
                call.agent.id = "guest-" + visitor.id
            } else if call.inCall {
                hangUp(call)
            }
        }
        calls = next + calls.filter(\.stranger)
        if !calls.contains(where: { $0.id == focusedID }) { focusedID = calls.first?.id ?? "" }
        listensForAnswers = config.listensForAnswers
        if guestSettings != config.guests {
            guestSettings = config.guests
            sweepIdleGuests()
            if config.guests == nil { for call in calls where call.visitor != nil { dismiss(call) } }
        }
    }

    func start() async {
        notifier.onAnswer = { [weak self] id, decision in
            guard let call = self?.calls.first(where: { $0.pendingApproval?.id == id }) else { return }
            self?.answer(call, decision: decision)
        }
        notifier.onOpen = { [weak self] id in
            guard let call = self?.calls.first(where: { $0.pendingApproval?.id == id || $0.id == id }) else { return }
            self?.focus(call)
        }
        notifier.onReply = { [weak self] id, text in
            guard let call = self?.calls.first(where: { $0.id == id && $0.questionText != nil }) else { return }
            self?.answerQuestion(of: call, with: text)
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

    func show(hint text: String) {
        hint = text
        hintTask?.cancel()
        hintTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            if !Task.isCancelled { hint = nil }
        }
    }

    func toggle(_ call: Call) {
        if call.guest { return dismiss(call) }
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
                previous.state = previous.idle
            }
            if previous.state == .speaking {
                speaker?.stop()
                previous.state = .thinking
            }
        }
        focusedID = call.id
        calls.removeAll { $0.stranger && !$0.inCall && $0 !== call }
    }

    func summon(_ call: Call) {
        guard readiness == .ready, !call.inCall else { return }
        guard !call.guest else { return }
        // A new attempt replaces the last setup problem instead of stacking another.
        call.lines.removeAll { $0.action == .openSettings }
        do {
            try microphone.open()
            call.thinking = call.thinkingNextCall ?? call.agent.thinking
            let session = try SessionMaker(environment: environment)
                .session(for: call.agent, thinking: call.thinking, prompt: callPrompt(for: call.agent))
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
                    knownThinking[call.id] = session.thinkingLevels
                }
            }
            Task { for await details in session.details { call.details = details } }
            Task { for await options in session.options { knownOptions[call.id] = options } }
            Task { for await turn in session.ownTurns { hear(turn, from: call) } }
            // After the state change that freed the call has run its course.
            call.becameReady = { [weak self, weak call] in
                Task { @MainActor in
                    if let self, let call { self.playWaitingTurn(in: call) }
                }
            }
            Task {
                for await problem in session.problems {
                    report(in: call, .init(role: .problem, text: "\(call.agent.name): \(problem)"))
                }
            }
            call.lines = []
            call.state = .ready
        } catch let error as SetupError {
            report(in: call, .init(role: .problem, text: error.message(for: call.agent.name), action: .openSettings))
        } catch {
            report(in: call, .init(role: .problem, text: "Couldn't start \(call.agent.name): \(error.localizedDescription)",
                                    action: .openSettings))
        }
    }

    /// A problem line, with its sound so it's noticed with the panel closed.
    func report(in call: Call, _ line: Call.Line) {
        Self.log.error("\(call.id, privacy: .public): \(line.text, privacy: .public)")
        call.lines.append(line)
        call.log(.problem(line.text))
        speaker?.play(.problem)
    }

    /// Hermes agents keep the identity they already have; local agents get their name and soul.
    private func callPrompt(for agent: AgentConfig) -> String {
        VoicePrompt.forCall(name: agent.name, soul: Souls.standard.soul(for: agent.id),
                            others: calls.filter { !$0.guest }.map(\.agent.name).filter { $0 != agent.name })
    }

    func hangUp(_ call: Call) {
        if call.pendingApproval != nil { answer(call, decision: .deny) }
        resolveQuestion(of: call, with: nil)
        call.context = []
        call.ownTurnsWaiting = []
        call.turn?.cancel()
        call.session?.stop()
        call.session = nil
        if call.state == .speaking { speaker?.stop() }
        // Other calls keep the microphone open; this one's capture must still end.
        if call.state == .listening { _ = try? microphone.stopCapture() }
        call.state = .offline
        call.unread = false
        call.unheard = []
        closeMicrophoneIfUnused()
    }

    /// Opened whenever Lair starts listening, not when a call or question starts: an answer elsewhere can close it
    /// in between. Opening an open microphone does nothing.
    func openMicrophone(for call: Call) -> Bool {
        do {
            try microphone.open()
            return true
        } catch {
            report(in: call, .init(role: .problem, text: "Can't listen: \(error.localizedDescription)"))
            return false
        }
    }

    /// Guests hold no call of their own: the microphone is only needed for a call or a question.
    func closeMicrophoneIfUnused() {
        if !calls.contains(where: { $0.visitor != nil ? $0.question != nil : $0.inCall }) { microphone.close() }
    }

    /// What the orb follows: your voice while it listens, its own while it speaks.
    func meter(for call: Call) -> LevelMeter? {
        switch call.state {
        case .listening: meterOverride ?? microphone.meter
        case .speaking: meterOverride ?? speaker?.meter
        default: nil
        }
    }

    static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "lair", category: "turn")

    static let clock = ContinuousClock()

    // MARK: Guests, agents on this Mac that joined over MCP

    /// Who spoke last and when, so a new voice says who it is.
    @ObservationIgnored var lastVoice: (id: String, at: Date)?

    /// The guest server's settings, from the config; nil while it's off.
    @ObservationIgnored var guestSettings: GuestSettings?
    @ObservationIgnored var idleSweep: Task<Void, Never>?

    /// Saves a new agent in the config and returns it with its id; set by the app.
    @ObservationIgnored var saveAgent: ((AgentConfig) -> AgentConfig?)?
}
