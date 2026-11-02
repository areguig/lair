/// A streamed reply on its way to the screen and the voice: `<show>` items kept off the voice, the rest cut into sentences.
public struct SpokenStream {
    public struct Piece: Equatable {
        /// What to append to the agent's line.
        public var text: String
        /// Links, paths and commands the agent showed instead of saying.
        public var shown: [String]
        /// Complete sentences, ready to say.
        public var sentences: [String]
    }

    private var filter = ShowFilter()
    private var splitter = SentenceSplitter()

    public init() {}

    /// `lineText` is what the agent's line holds so far, so two messages sent glued get their space.
    public mutating func feed(_ delta: String, after lineText: String) -> Piece {
        let visible = filter.feed(delta)
        let text = Speakable.gap(after: lineText, before: visible.spoken) + visible.spoken
        return Piece(text: text, shown: visible.shown, sentences: splitter.feed(text))
    }

    /// Ends the text so far, at an approval or the end of the turn, with whatever was held back for more.
    public mutating func finish() -> Piece {
        let visible = filter.flush()
        let sentences = splitter.feed(visible.spoken) + [splitter.flush()].compactMap(\.self)
        return Piece(text: visible.spoken, shown: visible.shown, sentences: sentences)
    }
}
