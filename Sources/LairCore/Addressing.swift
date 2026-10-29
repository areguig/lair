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
    /// `midSentence`: after "ask", where a capitalized word is a name even without a comma after it.
    static func leadingName(in text: Substring, names: [String], midSentence: Bool = false)
        -> (name: String, rest: Substring)? {
        // Longest first, so "Claude Code, …" isn't taken for "Claude" with "Code, …" left over.
        for name in names.filter({ !$0.isEmpty }).sorted(by: { $0.count > $1.count })
        where text.lowercased().hasPrefix(name.lowercased()) {
            let after = text.dropFirst(name.count)
            // The name must stand alone: "Echoes fade…" is not addressed to Echo.
            if let next = after.first, next.isLetter || next.isNumber { continue }
            return (name, after.drop { !$0.isLetter && !$0.isNumber })
        }
        // Speech recognition spells a name the way it sounds: "Saige" for Sage, "Cloud" for Claude.
        // Only a capitalized word counts, and at the start only before a pause: "Cloudy today" isn't Claude.
        let word = text.prefix { $0.isLetter }
        let after = text.dropFirst(word.count)
        guard word.count >= 3, word.first?.isUppercase == true, after.first?.isNumber != true,
              midSentence || after.first.map(",.!?:;".contains) == true,
              let name = names.first(where: { !$0.contains(" ") && soundKey($0) == soundKey(word) })
        else { return nil }
        return (name, after.drop { !$0.isLetter && !$0.isNumber })
    }

    /// Soundex, with the first letter coded like the rest so C and S or K sound alike.
    static func soundKey(_ word: some StringProtocol) -> String {
        let codes: [Character: Character] = [
            "b": "1", "f": "1", "p": "1", "v": "1",
            "c": "2", "g": "2", "j": "2", "k": "2", "q": "2", "s": "2", "x": "2", "z": "2",
            "d": "3", "t": "3", "l": "4", "m": "5", "n": "5", "r": "6",
        ]
        let letters = word.lowercased().filter(\.isLetter)
        guard let first = letters.first else { return "" }
        var key = String(codes[first] ?? first)
        var last = codes[first]
        for letter in letters.dropFirst() {
            // H and W don't separate two of the same sound; vowels do.
            if letter == "h" || letter == "w" { continue }
            let code = codes[letter]
            if let code, code != last { key.append(code) }
            last = code
        }
        return String(key.prefix(4)).padding(toLength: 4, withPad: "0", startingAt: 0)
    }
}
