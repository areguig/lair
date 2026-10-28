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
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
