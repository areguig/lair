import Foundation

/// Reads a spoken yes, always or no in the agent's language. Anything unclear is nil, so nothing is ever approved by accident.
public enum SpokenAnswer {
    public static func parse(_ transcript: String, language: Language) -> ApprovalDecision? {
        let words = transcript.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }
        let text = " " + words.joined(separator: " ") + " "
        func says(_ phrases: [String]) -> Bool { phrases.contains { text.contains(" \($0) ") } }
        let vocabulary = vocabulary(for: language)
        // Checked first, so "no, don't do it" or "do not allow" never count as yes.
        // Before the negations, because "don't ask again" contains "don".
        if says(vocabulary.always) && !says(vocabulary.negations) { return .allowAlways }
        if says(vocabulary.no) { return .deny }
        return says(vocabulary.yes) ? .allowOnce : nil
    }

    private struct Vocabulary {
        let always, no, yes: [String]
        /// Any of these takes "always" back ("never", "not always"), so it isn't approved by accident.
        let negations: [String]
    }

    private static func vocabulary(for language: Language) -> Vocabulary {
        switch language {
        case .english:
            Vocabulary(
                always: ["always", "don t ask again", "dont ask again", "don t ask me again", "dont ask me again"],
                no: ["no", "nope", "nah", "deny", "don", "dont", "not", "stop", "cancel", "never", "refuse", "reject"],
                yes: ["yes", "yeah", "yep", "yup", "sure", "allow", "approve", "ok", "okay", "go ahead", "do it",
                      "go for it", "absolutely", "please do"],
                negations: ["never", "not", "no"])
        case .french:
            Vocabulary(
                always: ["toujours", "ne me demande plus", "ne demande plus"],
                no: ["non", "refuse", "annule", "jamais", "arrête", "arrete", "stop"],
                yes: ["oui", "ouais", "ok", "okay", "d accord", "vas y", "allez y", "autorise", "bien sûr"],
                negations: ["jamais", "pas", "non"])
        }
    }
}
