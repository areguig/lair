import Foundation

/// Reads a spoken yes, always or no. Anything unclear is nil, so nothing is ever approved by accident.
public enum SpokenAnswer {
    public static func parse(_ transcript: String) -> ApprovalDecision? {
        let words = transcript.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }
        let text = " " + words.joined(separator: " ") + " "
        // Checked first, so "no, don't do it" or "do not allow" never count as yes.
        // Before the negations, because "don't ask again" contains "don".
        let saysAlways = ["always", "don t ask again", "dont ask again", "don t ask me again", "dont ask me again"]
            .contains { text.contains(" \($0) ") }
        let saysNo = ["no", "nope", "nah", "deny", "don", "dont", "not", "stop", "cancel", "never", "refuse", "reject"]
            .contains { text.contains(" \($0) ") }
        let saysYes = ["yes", "yeah", "yep", "yup", "sure", "allow", "approve", "ok", "okay", "go ahead", "do it",
                       "go for it", "absolutely", "please do"]
            .contains { text.contains(" \($0) ") }
        if saysAlways && !text.contains(" never ") && !text.contains(" not ") && !text.contains(" no ") { return .allowAlways }
        if saysNo { return .deny }
        return saysYes ? .allowOnce : nil
    }
}
