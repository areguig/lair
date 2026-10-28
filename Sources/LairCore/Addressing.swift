import Foundation

/// Finds who a sentence is for when it opens with an agent's name: "Echo, check the backups".
public enum Addressing {
    public static func split(_ text: String, names: [String]) -> (name: String, rest: String)? {
        var trimmed = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
        for greeting in ["hey ", "ok ", "okay "] where trimmed.lowercased().hasPrefix(greeting) {
            trimmed = trimmed.dropFirst(greeting.count)
        }
        // Longest first, so "Claude Code, …" isn't taken for "Claude" with "Code, …" left over.
        for name in names.filter({ !$0.isEmpty }).sorted(by: { $0.count > $1.count })
        where trimmed.lowercased().hasPrefix(name.lowercased()) {
            let after = trimmed.dropFirst(name.count)
            // The name must stand alone: "Echoes fade…" is not addressed to Echo.
            guard let next = after.first, !next.isLetter, !next.isNumber else { continue }
            let rest = after.drop { !$0.isLetter && !$0.isNumber }
            if !rest.isEmpty { return (name, String(rest)) }
        }
        return nil
    }
}
