import Foundation

/// A short imperative utterance aimed at Lair itself (model / thinking switches), not the coding agent.
public enum VoiceCommand: Equatable, Sendable {
    case model(String)
    case thinkMore
    case thinkLess
    case thinking(String)
    case fast
    case deep
    case answers(AgentConfig.Answers)

    /// nil when the transcript is a normal request for the agent.
    public static func parse(_ transcript: String) -> VoiceCommand? {
        // A question mark means a question, whatever the words say.
        if transcript.contains("?") { return nil }
        var words = normalize(transcript)
        stripFillers(&words)
        guard !words.isEmpty, words.count <= 7 else { return nil }
        if questionStarters.contains(words[0]) { return nil }

        switch words.joined(separator: " ") {
        case "think harder", "think more", "more thinking", "think deeper", "think hard": return .thinkMore
        case "think less", "less thinking", "stop overthinking": return .thinkLess
        case "go fast", "fast mode", "be quick", "quick mode": return .fast
        case "go deep", "deep mode", "take your time": return .deep
        case "be brief", "shorter answers", "short answers": return .answers(.brief)
        case "more detail", "more details", "longer answers", "be more detailed": return .answers(.detailed)
        case "normal answers": return .answers(.normal)
        default: break
        }
        if let level = thinkingLevel(words) { return .thinking(level) }
        return modelSwitch(words)
    }

    private static let questionStarters: Set<String> = [
        "why", "what", "how", "is", "does", "can", "should", "which", "when", "where", "who",
    ]
    private static let leadFillers: [[String]] = [["can", "you"], ["could", "you"], ["okay"], ["ok"], ["hey"], ["please"], ["now"]]
    private static let trailFillers: Set<String> = ["please", "now", "thanks"]
    // Words that make a "model name" a pronoun or generic reference.
    private static let notModel: Set<String> = [
        "it", "that", "this", "them", "those", "these", "another", "other", "one", "different", "a", "the",
        "something", "mode", "thinking", "effort",
    ]
    private static let modelPrefixes: [[String]] = [
        ["change", "the", "model", "to"], ["set", "the", "model", "to"], ["change", "model", "to"],
        ["switch", "model", "to"], ["set", "model", "to"], ["switch", "to"], ["go", "with"], ["use"],
    ]
    private static let levels: [String: String] = [
        "off": "off", "minimal": "minimal", "low": "low", "medium": "medium", "high": "high",
        "xhigh": "xhigh", "extra high": "xhigh", "x high": "xhigh", "max": "max", "maximum": "max",
    ]

    private static func normalize(_ text: String) -> [String] {
        let cleaned = text.lowercased().unicodeScalars.map { s -> Character in
            if s == "'" || s == "\u{2019}" { return "\u{0}" }  // drop apostrophes
            return CharacterSet.alphanumerics.contains(s) ? Character(s) : " "
        }
        return String(cleaned).replacingOccurrences(of: "\u{0}", with: "")
            .split(separator: " ").map(String.init)
    }

    private static func stripFillers(_ words: inout [String]) {
        var changed = true
        while changed {
            changed = false
            for f in leadFillers where words.count > f.count && Array(words.prefix(f.count)) == f {
                words.removeFirst(f.count)
                changed = true
                break
            }
        }
        while words.count > 1, let last = words.last, trailFillers.contains(last) { words.removeLast() }
    }

    private static func level(_ words: ArraySlice<String>) -> String? {
        levels[words.joined(separator: " ")]
    }

    private static func thinkingLevel(_ w: [String]) -> String? {
        let prefixes: [[String]] = [
            ["set", "thinking", "to"], ["set", "effort", "to"], ["thinking", "level"],
            ["use"], ["think"], ["thinking"], ["effort"],
        ]
        for p in prefixes where w.count > p.count && Array(w.prefix(p.count)) == p {
            let rest = w.dropFirst(p.count)
            if p == ["use"] {
                // "use <level> thinking|effort"
                if let last = rest.last, last == "thinking" || last == "effort" { return level(rest.dropLast()) }
                continue
            }
            if let l = level(rest) { return l }
        }
        // "<level> thinking" / "<level> effort"
        if let last = w.last, last == "thinking" || last == "effort" { return level(w.dropLast()) }
        return nil
    }

    private static func modelSwitch(_ w: [String]) -> VoiceCommand? {
        for p in modelPrefixes where w.count > p.count && Array(w.prefix(p.count)) == p {
            let name = Array(w.dropFirst(p.count))
            guard name.count <= 4, name.allSatisfy({ !notModel.contains($0) }) else { return nil }
            return .model(name.joined(separator: "-"))
        }
        return nil
    }
}
