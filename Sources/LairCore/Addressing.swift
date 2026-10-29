import Foundation

/// Finds who a sentence is for when it opens with an agent's name: "Echo, check the backups".
public enum Addressing {
    public static func split(_ text: String, names: [String]) -> (name: String, rest: String)? {
        guard let (name, rest) = leadingName(in: withoutGreeting(text), names: names), !rest.isEmpty else { return nil }
        return (name, String(rest))
    }

    static func withoutGreeting(_ text: String) -> Substring {
        var trimmed = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
        for greeting in ["hey ", "ok ", "okay "] where trimmed.lowercased().hasPrefix(greeting) {
            trimmed = trimmed.dropFirst(greeting.count)
        }
        return trimmed
    }

    /// The name the text starts with and what follows it, punctuation dropped; `rest` may be empty.
    static func leadingName(in text: Substring, names: [String]) -> (name: String, rest: Substring)? {
        // Longest first, so "Claude Code, …" isn't taken for "Claude" with "Code, …" left over.
        for name in names.filter({ !$0.isEmpty }).sorted(by: { $0.count > $1.count })
        where text.lowercased().hasPrefix(name.lowercased()) {
            let after = text.dropFirst(name.count)
            // The name must stand alone: "Echoes fade…" is not addressed to Echo.
            if let next = after.first, next.isLetter || next.isNumber { continue }
            return (name, after.drop { !$0.isLetter && !$0.isNumber })
        }
        return nil
    }
}
