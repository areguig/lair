import Foundation

/// "Nova, ask Claude what it thinks", or "ask Echo to do it" to the agent you're talking to:
/// a message for one agent, passed on by another.
public struct Relay: Equatable, Sendable {
    /// Who it's passed on from; nil means the agent in focus.
    public let source: String?
    public let target: String
    /// What you said, whole, so the target reads it the way you said it.
    public let words: String

    public init(source: String?, target: String, words: String) {
        self.source = source
        self.target = target
        self.words = words
    }

    public static func parse(_ text: String, names: [String]) -> Relay? {
        var rest = Addressing.withoutGreeting(text)
        let source = Addressing.leadingName(in: rest, names: names)
        if let source { rest = source.rest }
        for filler in ["please ", "can you ", "could you ", "would you "] where rest.lowercased().hasPrefix(filler) {
            rest = rest.dropFirst(filler.count)
        }
        guard let verb = verbs.first(where: { rest.lowercased().hasPrefix($0) }) else { return nil }
        let others = names.filter { $0.caseInsensitiveCompare(source?.name ?? "") != .orderedSame }
        guard let target = Addressing.leadingName(in: Addressing.withoutGreeting(String(rest.dropFirst(verb.count))),
                                                  names: others, midSentence: true),
              !target.rest.isEmpty
        else { return nil }
        return Relay(source: source?.name, target: target.name,
                     words: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // "asked": how speech recognition often hears "ask" before a name.
    private static let verbs = ["ask ", "asked ", "tell ", "have ", "get ", "let "]
}
