import Foundation
import LairACP
import LairCore
import LairMCP
import LairVoice
import Observation
import os

extension Room {
    /// A line of Lair's own, in the language the call's agent speaks.
    func phrase(_ phrase: Phrase, in call: Call) -> String {
        phrase.text(in: call.agent.spokenLanguage)
    }

    func say(_ sentence: String, in call: Call) async throws -> Bool {
        let text = Speakable.text(sentence)
        guard !silent, !text.isEmpty, let speaker else { return false }
        guard call.id == focusedID else {
            call.unheard.append(sentence)
            return false
        }
        let samples = try await voice.speech(for: text, voice: call.agent.voice, language: call.agent.spokenLanguage)
        // Hung up while the sentence was being synthesized: setting `.speaking` would bring the call back.
        guard call.inCall, !silent else { return false }
        // Focus may have moved while the sentence was being synthesized.
        guard !Task.isCancelled, call.id == focusedID else {
            call.unheard.append(sentence)
            return false
        }
        call.state = .speaking
        speaker.enqueue(samples) { [weak self, weak call] in
            if let self, let call, call.id == self.focusedID, call.state == .speaking { self.speaking = sentence }
        }
        return true
    }

    /// One line from a background agent, once the focused one has stopped talking.
    func announce(_ text: String, for call: Call) {
        guard !silent else { return }
        Task {
            await waitForTheFloor()
            guard !silent, let speaker, let samples = try? await voice.speech(for: text, voice: call.agent.voice, language: call.agent.spokenLanguage) else { return }
            guard !silent else { return }
            speaker.enqueue(samples)
        }
    }

    /// Returns whether the sentence was queued for playback; only the focused agent is heard.
    /// Speaks what the agent said in the background, once you switch to it and it isn't mid-turn.
    func replayUnheard(_ call: Call) {
        guard !silent else { return call.unheard = [] }
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

    /// Plays a group's sound once, so Settings can let you hear a change.
    func preview(sound group: SoundGroup) {
        speaker?.preview(group.preview)
    }

    /// Says a short line in `language`, so a voice can be tried before choosing it.
    func preview(voice: String, language: Language, name: String) {
        guard readiness == .ready, let speaker else { return }
        Task {
            guard let samples = try? await self.voice.speech(for: language.introduction(of: name), voice: voice, language: language) else { return }
            speaker.enqueue(samples)
        }
    }
}
