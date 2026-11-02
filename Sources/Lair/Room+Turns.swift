import Foundation
import LairACP
import LairCore
import LairMCP
import LairVoice
import Observation
import os

extension Room {
    func reply(in call: Call, to samples: [Float]) async {
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
        let others = calls.filter { $0.id != call.id && !$0.guest }
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

    /// "Ask Echo to check it", or "Nova, ask Claude what it thinks": the target answers, with the source's latest
    /// exchange as context, and the source hears what it said on its next turn. Returns whether `text` was one.
    func pass(_ text: String, from heard: Call, speech: Int, start: ContinuousClock.Instant) -> Bool {
        guard let relay = Relay.parse(text, names: calls.filter { !$0.guest }.map(\.agent.name)),
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
                           shown: .init(role: .you, text: relay.words), typed: speech == 0)
            guard source.inCall, let answer = target.lines.dropFirst(before)
                .last(where: { $0.role == .agent && !$0.text.isEmpty })?.text else { return }
            source.context.append(VoicePrompt.relayed(relay.words, to: target.agent.name, answer: answer))
        }
        return true
    }

    private func call(named name: String) -> Call? {
        calls.first { !$0.guest && $0.agent.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    private func step(_ by: Int, from current: String?, in levels: [String]) -> String? {
        guard !levels.isEmpty else { return nil }
        let index = current.flatMap { levels.firstIndex(of: $0) } ?? levels.firstIndex(of: "medium") ?? levels.count / 2
        return levels[min(max(index + by, 0), levels.count - 1)]
    }

    /// The agent took a turn by itself, such as telling what its background work found.
    func hear(_ turn: AgentTurn, from call: Call) {
        guard call.inCall else { return }
        call.ownTurnsWaiting.append(turn)
        playWaitingTurn(in: call)
    }

    func playWaitingTurn(in call: Call) {
        guard call.inCall, call.state == .ready, call.pendingApproval == nil, !call.ownTurnsWaiting.isEmpty else { return }
        let turn = call.ownTurnsWaiting.removeFirst()
        call.state = .thinking
        call.turn = Task {
            await play({ turn }, in: call, speech: 0, start: Self.clock.now, opening: .init(role: .info, text: "Back with news"))
        }
    }

    /// `shown` replaces the prompt in the transcript when the prompt isn't something you said.
    func converse(in call: Call, prompt: String, speech: Int, start: ContinuousClock.Instant,
                          shown: Call.Line? = nil, typed: Bool = false) async {
        guard let session = call.session else { return }
        call.lines.append(shown ?? .init(role: .you, text: prompt))
        call.log(shown.map { $0.role == .you ? .you($0.text) : .note($0.text) } ?? .you(prompt))
        let sent = (call.context + [prompt]).joined(separator: "\n\n")
        call.context = []
        await play({ try session.ask(sent) }, in: call, speech: speech, start: start, typed: typed)
    }

    /// Speaks a turn as it comes, asked or the agent's own. `opening` heads an own turn once it says something;
    /// one with nothing to say passes silently.
    /// Speaks a turn as it comes, asked or the agent's own. `opening` heads an own turn once it says something;
    /// one with nothing to say passes silently.
    private func play(_ turn: () throws -> AgentTurn, in call: Call, speech: Int, start: ContinuousClock.Instant,
                      typed: Bool = false, opening: Call.Line? = nil) async {
        let turnID = UUID()
        call.turnID = turnID
        call.unheard = []
        Self.log.notice("\(call.id, privacy: .public): \(opening == nil ? "turn sent" : "agent took a turn of its own", privacy: .public)")
        // The agent spoke to you: listen a few seconds for your reply. Typed turns don't open the mic.
        var listenAfter = false
        defer {
            if call.inCall, call.turnID == turnID {
                call.state = .ready
                if !call.ownTurnsWaiting.isEmpty { playWaitingTurn(in: call) } else if listenAfter { listenForAnswer(in: call) }
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
            guard let speaker else { return }
            // Text after an approval starts a new line, so the transcript reads in order.
            var answer: Int?
            var answered = false
            var splitter = SentenceSplitter()
            // Links and paths in <show> tags go to the screen, never to the voice.
            var showing = ShowFilter()
            for try await reply in try turn() {
                guard !Task.isCancelled else { return }
                switch reply {
                case .activity(let activity):
                    call.record(activity)
                    logTool(activity, in: call)
                case .text(let delta):
                    if firstToken == nil { firstToken = clock.now - start }
                    if !answered, let opening {
                        call.lines.append(opening)
                        call.log(.note(opening.text))
                    }
                    call.logText(delta)
                    if answer == nil {
                        call.lines.append(.init(role: .agent, text: ""))
                        answer = call.lines.count - 1
                    }
                    let visible = showing.feed(delta)
                    let spoken = Speakable.gap(after: call.lines[answer!].text, before: visible.spoken) + visible.spoken
                    call.lines[answer!].text += spoken
                    call.lines[answer!].shown += visible.shown
                    answered = true
                    for sentence in splitter.feed(spoken) where try await say(sentence, in: call) && firstAudio == nil {
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
            // Cutting in ends the stream as if the turn were over; it was stopped, not silent.
            guard !Task.isCancelled, call.turnID == turnID else { return }
            let visible = showing.flush()
            if let answer {
                call.lines[answer].text += visible.spoken
                call.lines[answer].shown += visible.shown
            }
            for sentence in splitter.feed(visible.spoken) { _ = try await say(sentence, in: call) }
            if let rest = splitter.flush(), try await say(rest, in: call), firstAudio == nil {
                firstAudio = clock.now - start
            }
            if !answered, opening == nil {
                report(in: call, .init(role: .problem, text: "\(call.agent.name) didn't answer."))
            }
            if call.id == focusedID {
                await speaker.waitUntilDone()
                listenAfter = answered && !typed
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

    /// A tool's start and end, without its name: with ACP the name is often the command itself.
    private func logTool(_ activity: Activity, in call: Call) {
        switch activity {
        case .toolStarted: Self.log.notice("\(call.id, privacy: .public): tool started")
        case .toolFinished(_, _, let failed): Self.log.notice("\(call.id, privacy: .public): tool \(failed ? "failed" : "finished", privacy: .public)")
        default: break
        }
    }

    /// Puts the request in front of you three ways at once; the turn stays paused until `answer`.
    private func ask(_ call: Call, to request: ApprovalRequest) async throws {
        call.pendingApproval = request
        call.log(.approval("\(request.tool): \(request.summary)"))
        Self.log.notice("\(call.id, privacy: .public): approval asked\(call.id == self.focusedID ? "" : " while not in focus", privacy: .public)")
        notifier.post(request, from: call.agent.name)
        speaker?.play(.needsYou)
        if call.id != focusedID {
            call.unread = true
            call.state = .waiting
            announce("\(call.agent.name) needs your OK.", for: call)
            return
        }
        _ = try await say("\(call.agent.name) needs your OK to \(request.spoken.lowercasedFirst). Allow it?" + (request.canAlwaysAllow ? " Say yes, always, or no." : " Say yes or no."), in: call)
        if call.pendingApproval?.id == request.id { call.state = .waiting }
        await speaker?.waitUntilDone()
        if call.pendingApproval?.id == request.id { listenForAnswer(in: call) }
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
        Self.log.notice("\(call.id, privacy: .public): approval answered, \(verdict, privacy: .public)")
        do {
            try call.session?.answer(request, decision: decision)
            if call.state == .waiting { call.state = .thinking }
        } catch {
            report(in: call, .init(role: .problem, text: error.localizedDescription))
        }
    }

    func interrupt(_ call: Call) {
        Self.log.notice("\(call.id, privacy: .public): interrupted")
        if call.id == focusedID { speaker?.stop() }
        call.turnID = nil
        call.turn?.cancel()
        call.session?.interrupt()
        call.state = .ready
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
}

private extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
