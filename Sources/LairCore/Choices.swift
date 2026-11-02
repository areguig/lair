import Foundation

/// The options an agent offers with a question, and which one an answer, heard or typed, picks.
public enum Choices {
    private static let ordinals: [Language: [String: Int]] = [
        .english: [
            "1": 0, "one": 0, "first": 0, "2": 1, "two": 1, "second": 1, "3": 2, "three": 2, "third": 2,
            "4": 3, "four": 3, "fourth": 3, "5": 4, "five": 4, "fifth": 4, "6": 5, "six": 5, "sixth": 5,
        ],
        // No "un" or "une": they are articles far more often than numbers.
        .french: [
            "1": 0, "premier": 0, "première": 0, "2": 1, "deux": 1, "deuxième": 1, "second": 1, "seconde": 1,
            "3": 2, "trois": 2, "troisième": 2, "4": 3, "quatre": 3, "quatrième": 3, "5": 4, "cinq": 4,
            "cinquième": 4, "6": 5, "six": 5, "sixième": 5,
        ],
    ]

    /// The choice the answer names ("blue", "go with blue"), or else the one its number points at ("the second one",
    /// "2", "la deuxième" in French); nil when it's neither, so the answer goes to the agent as it was said.
    public static func pick(_ answer: String, from choices: [String], language: Language) -> String? {
        var said = words(answer)
        // "les deux" means both, not the second.
        if language == .french {
            let before = [""] + said
            said = zip(before, said).filter { !($0 == "les" && $1 == "deux") }.map { $1 }
        }
        guard !said.isEmpty, !choices.isEmpty else { return nil }
        if let exact = choices.first(where: { words($0) == said }) { return exact }
        let named = choices.filter { choice in
            let wanted = words(choice)
            return !wanted.isEmpty && said.count >= wanted.count
                && (0...(said.count - wanted.count)).contains { Array(said[$0..<$0 + wanted.count]) == wanted }
        }
        if named.count == 1 { return named[0] }
        // In "the second one", "one" only stands for the choice.
        let numbered = ordinals[language]!
        let counted = said.contains { $0 != "one" && numbered[$0] != nil } ? said.filter { $0 != "one" } : said
        let numbers = Set(counted.compactMap { numbered[$0] }).filter { $0 < choices.count }
        return numbers.count == 1 ? choices[numbers.first!] : nil
    }

    /// "Red, green or blue." ("rouge, vert ou bleu."), said after a question that doesn't already name them.
    public static func spoken(_ choices: [String], after question: String, language: Language) -> String? {
        guard choices.count > 1 else { return nil }
        let asked = words(question)
        guard !choices.allSatisfy({ choice in words(choice).allSatisfy(asked.contains) }) else { return nil }
        return choices.dropLast().joined(separator: ", ") + (language == .french ? " ou " : " or ") + choices.last! + "."
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}
