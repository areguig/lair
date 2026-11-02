import Foundation
import LairACP
import LairCore
import LairMCP
import LairVoice
import Observation
import os

extension Room {
    func say(_ sentence: String, in call: Call) async throws -> Bool {
        let text = Speakable.text(sentence)
        guard !text.isEmpty, let speaker else { return false }
        guard call.id == focusedID else {
            call.unheard.append(sentence)
            return false
        }
        let samples = try await voice.speech(for: text, voice: call.agent.voice)
        // Hung up while the sentence was being synthesized: setting `.speaking` would bring the call back.
        guard call.inCall else { return false }
        // Focus may have moved while the sentence was being synthesized.
        guard !Task.isCancelled, call.id == focusedID else {
            call.unheard.append(sentence)
            return false
        }
        speaker.enqueue(samples)
        call.state = .speaking
        return true
    }

    /// One line from a background agent, once the focused one has stopped talking.
    func announce(_ text: String, for call: Call) {
        Task {
            await waitForTheFloor()
            guard let speaker, let samples = try? await voice.speech(for: text, voice: call.agent.voice) else { return }
            speaker.enqueue(samples)
        }
    }

    /// Returns whether the sentence was queued for playback; only the focused agent is heard.
    /// Speaks what the agent said in the background, once you switch to it and it isn't mid-turn.
    func replayUnheard(_ call: Call) {
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

    /// Until the focused agent has stopped talking and you've stopped answering.
    func waitForTheFloor() async {
        while let current = focused, current.state == .speaking || current.state == .listening || answering != nil {
            try? await Task.sleep(for: .milliseconds(300))
        }
    }

    /// Says a short line in `voice`, so a voice can be tried before choosing it.
    func preview(voice: String, name: String) {
        guard readiness == .ready, let speaker else { return }
        Task {
            guard let samples = try? await self.voice.speech(for: "Hi, I'm \(name).", voice: voice) else { return }
            speaker.enqueue(samples)
        }
    }
}
