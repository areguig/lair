import Foundation

/// Strips markdown an agent may still send, so the voice doesn't read out symbols.
public enum Speakable {
    public static func text(_ markdown: String) -> String {
        var text = markdown
        // [label](url) → label
        text = text.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        // List bullets and heading marks at the start of a line.
        text = text.replacingOccurrences(of: #"(?m)^\s*(#+|[-*+]|\d+\.)\s+"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"[*_`~#>|]"#, with: "", options: .regularExpression)
        // A rule like "---" or a lone "…" has nothing to say, and the voice model fails on it.
        guard text.contains(where: { $0.isLetter || $0.isNumber }) else { return "" }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A name said the way people say it: short lowercase names like "omp" are initials, spelled out.
    public static func name(_ name: String) -> String {
        guard name.count <= 4, name == name.lowercased(), name.allSatisfy(\.isLetter) else { return name }
        return name.uppercased().map(String.init).joined(separator: " ")
    }

    /// A space between two pieces of an answer that arrive glued, "night." then "Nothing": an agent sends each of its
    /// messages without one.
    public static func gap(after text: String, before next: String) -> String {
        guard let last = text.last, ".!?".contains(last), let first = next.first, first.isUppercase else { return "" }
        return " "
    }
}
