import Foundation
import LairACP
import LairCore
import LairMCP
import LairVoice
import Observation
import os

extension Room {
    /// "omp says, …" when the voice changes or hasn't been heard for a while; just the words otherwise.
    private func introduce(_ text: String, by call: Call, verb: String) -> String {
        defer { lastVoice = (call.id, .now) }
        if let lastVoice, lastVoice.id == call.id, Date.now.timeIntervalSince(lastVoice.at) < 90 { return text }
        return "\(Speakable.name(call.agent.name)) \(verb), \(text)"
    }

    /// The session's call, joining the room on its first word: as your agent with its tool and folder when that
    /// agent is free, otherwise on its own, numbered after anyone with the same name. Not private so snapshots can
    /// stage one.
    func call(for guest: Guest) -> Call {
        if let call = calls.first(where: { $0.visitor?.id == guest.id }) {
            call.heard = .now
            if call.folder == nil { call.folder = guest.folder }
            return call
        }
        let call = arrival(of: guest)
        call.visitor = guest
        call.folder = guest.folder
        call.state = .ready
        call.heard = .now
        Self.log.notice("\(call.id, privacy: .public): \(guest.name, privacy: .public) joined as \(call.agent.name, privacy: .public) from \(guest.folder?.path ?? "no folder", privacy: .public)")
        return call
    }

    private func arrival(of guest: Guest) -> Call {
        let match = Visitors.agent(client: guest.client, folder: guest.folder, in: calls.filter { !$0.stranger }.map(\.agent))
        if let match, let call = calls.first(where: { $0.id == match.id }), call.visitor == nil, !call.inCall {
            call.lines.append(.init(role: .info, text: "Joined from your terminal."))
            return call
        }
        let used = Set(calls.map(\.agent.voice)), colors = Set(calls.map(\.agent.color))
        let agent = AgentConfig(id: "guest-" + guest.id, name: Visitors.name(match?.name ?? guest.name, taken: Set(calls.map(\.agent.name))),
                                kind: .guest,
                                voice: match?.voice ?? VoiceModels.voices.first { !used.contains($0) } ?? "af_heart",
                                color: match?.color ?? AgentConfig.palette.first { !colors.contains($0) }
                                    ?? AgentConfig.palette[calls.count % AgentConfig.palette.count])
        let call = Call(agent: agent)
        calls.append(call)
        return call
    }

    /// A session of a tool Lair knows, in a folder none of your agents has, can become one.
    func canAdopt(_ call: Call) -> Bool {
        guard call.stranger, let visitor = call.visitor, Visitors.preset(ofClient: visitor.client) != nil, call.folder != nil
        else { return false }
        return Visitors.agent(client: visitor.client, folder: call.folder, in: calls.filter { !$0.stranger }.map(\.agent)) == nil
    }

    /// Saves the session's tool and folder as an agent named after the folder, with the voice and color it has now;
    /// its next sessions there join as that agent.
    func adopt(_ call: Call) {
        guard canAdopt(call), let preset = Visitors.preset(ofClient: call.visitor?.client), let folder = call.folder else { return }
        let draft = AgentConfig(id: "", name: Visitors.agentName(for: folder), preset: preset, voice: call.agent.voice,
                                color: call.agent.color, directory: Visitors.configPath(folder))
        guard let saved = saveAgent?(draft) else { return }
        // Its id changes with it: keep pointing at it wherever the old one was used.
        let old = call.id
        call.agent = saved
        if focusedID == old { focusedID = saved.id }
        if answering?.callID == old { answering = Answering(callID: saved.id, since: answering!.since, hearing: answering!.hearing) }
        if call.questionText != nil { notifier.remove(old) }
        call.lines.append(.init(role: .info, text: "Saved as \(saved.name): its sessions in this folder join as \(saved.name)."))
    }

    /// Takes the floor only from someone who isn't on a call; otherwise heard once the floor is free.
    func guestSpeaks(_ text: String, from guest: Guest) async {
        let call = call(for: guest)
        call.lines.append(.init(role: .agent, text: text))
        call.logText(text)
        guard readiness == .ready, let speaker else { return call.unread = call.id != focusedID }
        await waitForTheFloor()
        if focused.map({ !$0.inCall || ($0.guest && !$0.awaitsYou) }) ?? true { focus(call) }
        guard call.id == focusedID else {
            call.unread = true
            return announce(text, for: call)
        }
        var splitter = SentenceSplitter()
        for sentence in splitter.feed(introduce(text, by: call, verb: "says")) + [splitter.flush()].compactMap(\.self) {
            _ = try? await say(sentence, in: call)
        }
        await speaker.waitUntilDone()
        if call.state == .speaking { call.state = call.idle }
    }

    /// One question at a time takes the floor once it's free, is asked aloud and listened for; it's also answered
    /// in the panel, Mission Control or the notification. The agent hearing nothing gets nil.
    func guestAsks(_ question: String, choices: [String] = [], from guest: Guest) async -> String? {
        let call = call(for: guest)
        guard readiness == .ready, call.question == nil else { return nil }
        call.logText(question)
        while calls.contains(where: { $0.question != nil }) || focused?.state == .speaking || focused?.state == .listening
                || answering != nil {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, call.visitor?.id == guest.id, calls.contains(where: { $0 === call }) else { return nil }
        }
        let wait = Duration.seconds(guestSettings?.answerSeconds ?? GuestSettings.standard.answerSeconds)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
                call.question = continuation
                call.questionText = question
                call.questionChoices = choices
                call.questionSince = .now
                call.questionDeadline = .now + TimeInterval(wait / .seconds(1))
                focus(call)
                call.state = .waiting
                notifier.postQuestion(question, choices: choices, id: call.id, from: call.agent.name)
                speaker?.play(.needsYou)
                Task {
                    let spoken = [question, Choices.spoken(choices, after: question)].compactMap { $0 }.joined(separator: " ")
                    _ = try? await say(introduce(spoken, by: call, verb: "asks"), in: call)
                    await speaker?.waitUntilDone()
                    if call.question != nil {
                        call.state = .waiting
                        listenForAnswer(in: call)
                    }
                }
                Task {
                    try? await Task.sleep(for: wait)
                    if call.questionText == question { resolveQuestion(of: call, with: nil, note: "No answer in time.") }
                }
            }
        } onCancel: {
            Task { @MainActor in self.resolveQuestion(of: call, with: nil, note: "\(call.agent.name) stopped waiting.") }
        }
    }

    /// You'd rather not answer: the agent hears that and carries on.
    func skipQuestion(of call: Call) {
        resolveQuestion(of: call, with: nil, note: "Skipped.")
    }

    func guestLeft(_ guest: Guest) {
        guard let call = calls.first(where: { $0.visitor?.id == guest.id }) else { return }
        leave(call, note: "Left.")
    }

    private func leave(_ call: Call, note: String) {
        resolveQuestion(of: call, with: nil, note: "\(call.agent.name) left before you answered.")
        if call.state == .speaking { stopSpeaking() }
        if call.state == .listening { _ = try? microphone.stopCapture() }
        call.visitor = nil
        call.state = .offline
        call.lines.append(.init(role: .info, text: note))
        // Your agent stays in the room; a stranger goes, but not while you're looking at its last words.
        if call.stranger, call.id != focusedID { calls.removeAll { $0 === call } }
        closeMicrophoneIfUnused()
    }

    /// Dismissed from the panel: out of the room now, and back on its next word.
    func dismiss(_ call: Call) {
        resolveQuestion(of: call, with: nil, note: "Dismissed.")
        if call.state == .speaking { stopSpeaking() }
        if call.state == .listening { _ = try? microphone.stopCapture() }
        call.visitor = nil
        call.state = .offline
        if call.stranger { calls.removeAll { $0 === call } }
        if !calls.contains(where: { $0.id == focusedID }) { focusedID = calls.first?.id ?? "" }
        closeMicrophoneIfUnused()
    }

    func hearReply(in call: Call, from samples: [Float]) async {
        let heard = (try? await voice.transcribe(samples)) ?? ""
        guard call.question != nil else { return }
        if heard.isEmpty { return call.state = .waiting }
        resolveQuestion(of: call, with: Choices.pick(heard, from: call.questionChoices) ?? heard)
    }

    /// Typed or clicked in the question card, or in the notification; "2" picks the second choice.
    func answerQuestion(of call: Call, with typed: String) {
        let typed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return }
        let text = Choices.pick(typed, from: call.questionChoices) ?? typed
        if call.state == .listening { _ = try? microphone.stopCapture() }
        if answering?.callID == call.id { answering = nil }
        resolveQuestion(of: call, with: text)
    }

    /// The first answer wins; nil tells the guest you didn't answer, and `note` tells you why.
    func resolveQuestion(of call: Call, with answer: String?, note: String = "No answer given.") {
        guard let question = call.question else { return }
        // Shown in its card while it waits; the transcript gets it once it's answered.
        if let asked = call.questionText { call.lines.append(.init(role: .agent, text: asked)) }
        call.question = nil
        call.questionText = nil
        call.questionChoices = []
        call.questionSince = nil
        call.questionDeadline = nil
        notifier.remove(call.id)
        if let answer {
            call.lines.append(.init(role: .you, text: answer))
            call.log(.you(answer))
        } else {
            call.lines.append(.init(role: .info, text: note))
            call.log(.note(note))
        }
        Self.log.notice("\(call.id, privacy: .public): \(answer == nil ? "no answer" : "answered", privacy: .public)")
        if call.state == .listening { _ = try? microphone.stopCapture() }
        if answering?.callID == call.id { answering = nil }
        if call.inCall { call.state = .ready }
        question.resume(returning: answer)
        closeMicrophoneIfUnused()
    }

    /// Claude Code never says it's gone, so a guest quiet for long enough leaves on its own.
    func sweepIdleGuests() {
        idleSweep?.cancel()
        guard let minutes = guestSettings?.idleMinutes else { return }
        idleSweep = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                let cutoff = Date.now - TimeInterval(minutes * 60)
                for call in calls where call.visitor != nil && !call.awaitsYou && call.heard < cutoff {
                    leave(call, note: "Quiet for \(minutes) minutes, so it left. It's back on its next word.")
                }
            }
        }
    }
}


/// Hands MCP guests to the room on the main actor.
struct RoomGuests: GuestHost {
    let room: Room

    func speak(_ text: String, from guest: Guest) async { await room.guestSpeaks(text, from: guest) }

    func ask(_ question: String, choices: [String], from guest: Guest) async -> String? {
        await room.guestAsks(question, choices: choices, from: guest)
    }

    func left(_ guest: Guest) async { await room.guestLeft(guest) }
}
