import Foundation
import LairACP
import LairCore
import LairMCP
import LairVoice
import Observation
import os

extension Room {
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
        releaseHold()
        if !call.inCall { summon(call) }
        // Talking over the agent cuts it off.
        if call.pendingApproval == nil, call.state == .speaking || call.state == .thinking {
            interrupt(call)
            call.lines.append(.init(role: .info, text: phrase(.youCutIn, in: call)))
        }
        guard call.state == .ready || call.state == .waiting else { return }
        if call.guest, call.question == nil { return show(hint: "\(call.agent.name) listens only when it asks you something.") }
        guard openMicrophone(for: call) else { return }
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
        guard samples.count >= minimumSpeech else {
            call.state = call.idle
            return
        }
        call.state = .thinking
        speaker?.play(.sent)
        if call.question != nil {
            Task { await hearReply(in: call, from: samples) }
        } else if call.pendingApproval != nil {
            Task { await hearAnswer(in: call, from: samples) }
        } else {
            call.turn = Task { await reply(in: call, to: samples) }
        }
    }

    private func hearAnswer(in call: Call, from samples: [Float]) async {
        let heard = (try? await voice.transcribe(samples)) ?? ""
        guard call.pendingApproval != nil else { return }
        if let decision = SpokenAnswer.parse(heard, language: call.agent.spokenLanguage) {
            answer(call, decision: decision)
        } else {
            if silent { show(hint: "Didn't catch that; say yes or no, or use the buttons.") }
            _ = try? await say(phrase(.sayYesOrNo(canAlwaysAllow: call.pendingApproval?.canAlwaysAllow == true), in: call), in: call)
            call.state = .waiting
            await speaker?.waitUntilDone()
            if call.pendingApproval != nil { listenForAnswer(in: call) }
        }
    }

    /// The microphone opens on its own after the agent speaks and sends once you've answered; silence closes it.
    /// Opening only after the voice has finished keeps the agent from hearing itself.
    func listenForAnswer(in call: Call) {
        guard listensForAnswers, !silent else { return }
        Task {
            guard var detector = await voice.detector(), readiness == .ready, call.id == focusedID,
                  call.state == .ready || call.state == .waiting, !microphone.isCapturing
            else { return }
            guard openMicrophone(for: call) else { return }
            speaker?.play(.yourTurn)
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
                    call.state = call.idle
                }
                break
            }
            if answering?.callID == call.id { answering = nil }
        }
    }

    /// Text typed in Mission Control: the same as saying it, without the microphone.
    func type(_ text: String, to call: Call) {
        guard readiness == .ready else { return show(hint: "Still getting the voices ready…") }
        focus(call)
        releaseHold()
        if !call.inCall { summon(call) }
        if let request = call.pendingApproval {
            guard let decision = SpokenAnswer.parse(text, language: call.agent.spokenLanguage) else {
                return show(hint: "Type yes" + (request.canAlwaysAllow ? ", always" : "") + " or no, or use the buttons.")
            }
            return answer(call, decision: decision)
        }
        if call.questionText != nil { return answerQuestion(of: call, with: text) }
        if call.guest { return show(hint: "\(call.agent.name) listens only when it asks you something.") }
        if call.state == .speaking || call.state == .thinking { interrupt(call) }
        guard call.state == .ready else { return }
        if pass(text, from: call, speech: 0, start: Self.clock.now) { return }
        if let command = VoiceCommand.parse(text, language: call.agent.spokenLanguage) {
            call.lines.append(.init(role: .you, text: text))
            call.log(.you(text))
            Task { await run(command, in: call) }
            return
        }
        call.state = .thinking
        call.turn = Task { await converse(in: call, prompt: text, speech: 0, start: Self.clock.now, typed: true) }
    }
}
