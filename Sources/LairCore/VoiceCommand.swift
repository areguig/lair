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
    /// Silent mode on or off.
    case silent(Bool)

    /// nil when the transcript is a normal request for the agent. Each language has its own phrases, so an English
    /// agent never reacts to French and the other way round.
    public static func parse(_ transcript: String, language: Language) -> VoiceCommand? {
        // A question mark means a question, whatever the words say.
        if transcript.contains("?") { return nil }
        let vocabulary = vocabulary(for: language)
        var words = normalize(transcript)
        stripFillers(&words, vocabulary)
        guard !words.isEmpty, words.count <= 7 else { return nil }
        if vocabulary.questionStarters.contains(words[0]) { return nil }

        if let command = vocabulary.phrases[words.joined(separator: " ")] { return command }
        // The levels are the agents' own English words, so they are only understood in English.
        if language == .english, let level = thinkingLevel(words) { return .thinking(level) }
        return modelSwitch(words, vocabulary)
    }

    private struct Vocabulary {
        let phrases: [String: VoiceCommand]
        let questionStarters: Set<String>
        let leadFillers: [[String]]
        let trailFillers: [[String]]
        /// Words that make a "model name" a pronoun or generic reference.
        let notModel: Set<String>
        let modelPrefixes: [[String]]
    }

    private static func vocabulary(for language: Language) -> Vocabulary {
        switch language {
        case .english: english
        case .french: french
        }
    }

    private static let english = Vocabulary(
        phrases: [
            "think harder": .thinkMore, "think more": .thinkMore, "more thinking": .thinkMore,
            "think deeper": .thinkMore, "think hard": .thinkMore,
            "think less": .thinkLess, "less thinking": .thinkLess, "stop overthinking": .thinkLess,
            "go fast": .fast, "fast mode": .fast, "be quick": .fast, "quick mode": .fast,
            "go deep": .deep, "deep mode": .deep, "take your time": .deep,
            "be brief": .answers(.brief), "shorter answers": .answers(.brief), "short answers": .answers(.brief),
            "more detail": .answers(.detailed), "more details": .answers(.detailed),
            "longer answers": .answers(.detailed), "be more detailed": .answers(.detailed),
            "normal answers": .answers(.normal),
            "go silent": .silent(true), "silent mode": .silent(true),
            "speak again": .silent(false), "talk to me again": .silent(false),
        ],
        questionStarters: ["why", "what", "how", "is", "does", "can", "should", "which", "when", "where", "who"],
        leadFillers: [["can", "you"], ["could", "you"], ["okay"], ["ok"], ["hey"], ["please"], ["now"]],
        trailFillers: [["please"], ["now"], ["thanks"]],
        notModel: ["it", "that", "this", "them", "those", "these", "another", "other", "one", "different", "a", "the",
                   "something", "mode", "thinking", "effort"],
        modelPrefixes: [["change", "the", "model", "to"], ["set", "the", "model", "to"], ["change", "model", "to"],
                        ["switch", "model", "to"], ["set", "model", "to"], ["switch", "to"], ["go", "with"], ["use"]])

    // Accents are folded away before matching, so these are written without them.
    private static let french = Vocabulary(
        phrases: [
            "reflechis plus": .thinkMore, "reflechis davantage": .thinkMore, "plus de reflexion": .thinkMore,
            "reflechis moins": .thinkLess, "moins de reflexion": .thinkLess, "arrete de trop reflechir": .thinkLess,
            "mode rapide": .fast, "sois rapide": .fast,
            "prends ton temps": .deep, "mode reflexion": .deep, "reflechis a fond": .deep,
            "sois bref": .answers(.brief), "sois concis": .answers(.brief), "reponses courtes": .answers(.brief),
            "reponses breves": .answers(.brief),
            "plus de details": .answers(.detailed), "donne plus de details": .answers(.detailed),
            "reponses detaillees": .answers(.detailed), "reponses plus longues": .answers(.detailed),
            "reponses normales": .answers(.normal),
            "mode silencieux": .silent(true), "passe en mode silencieux": .silent(true), "tais toi": .silent(true),
            "reparle moi": .silent(false), "mode vocal": .silent(false),
        ],
        questionStarters: ["pourquoi", "quoi", "quest", "comment", "est", "quel", "quelle", "quand", "qui", "combien"],
        leadFillers: [["peux", "tu"], ["tu", "peux"], ["ok"], ["okay"], ["alors"], ["maintenant"]],
        trailFillers: [["stp"], ["sil", "te", "plait"], ["sil", "vous", "plait"], ["merci"], ["maintenant"]],
        notModel: ["le", "la", "les", "l", "un", "une", "des", "ca", "cela", "ce", "cette", "autre", "suivant", "suivante",
                   "suite", "prochain", "prochaine", "mode", "reflexion", "etape", "question"],
        modelPrefixes: [["passe", "a"], ["passe", "sur"], ["bascule", "sur"], ["change", "de", "modele", "pour"]])

    private static let levels: [String: String] = [
        "off": "off", "minimal": "minimal", "low": "low", "medium": "medium", "high": "high",
        "xhigh": "xhigh", "extra high": "xhigh", "x high": "xhigh", "max": "max", "maximum": "max",
    ]

    private static func normalize(_ text: String) -> [String] {
        let cleaned = text.lowercased().folding(options: .diacriticInsensitive, locale: nil).unicodeScalars.map { s -> Character in
            if s == "'" || s == "\u{2019}" { return "\u{0}" }  // drop apostrophes
            return CharacterSet.alphanumerics.contains(s) ? Character(s) : " "
        }
        return String(cleaned).replacingOccurrences(of: "\u{0}", with: "")
            .split(separator: " ").map(String.init)
    }

    private static func stripFillers(_ words: inout [String], _ vocabulary: Vocabulary) {
        var changed = true
        while changed {
            changed = false
            for f in vocabulary.leadFillers where words.count > f.count && Array(words.prefix(f.count)) == f {
                words.removeFirst(f.count)
                changed = true
                break
            }
        }
        while let f = vocabulary.trailFillers.first(where: { words.count > $0.count && Array(words.suffix($0.count)) == $0 }) {
            words.removeLast(f.count)
        }
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

    private static func modelSwitch(_ w: [String], _ vocabulary: Vocabulary) -> VoiceCommand? {
        for p in vocabulary.modelPrefixes where w.count > p.count && Array(w.prefix(p.count)) == p {
            let name = Array(w.dropFirst(p.count))
            guard name.count <= 4, name.allSatisfy({ !vocabulary.notModel.contains($0) }) else { return nil }
            return .model(name.joined(separator: "-"))
        }
        return nil
    }
}
