/// Splits streamed reply text into spoken text and `<show>…</show>` items (seen, not spoken).
public struct ShowFilter: Sendable {
    public struct Output: Equatable, Sendable {
        public var spoken: String
        public var shown: [String]
        public init(spoken: String = "", shown: [String] = []) {
            self.spoken = spoken
            self.shown = shown
        }
    }

    private static let open = Array("<show>")
    private static let close = Array("</show>")

    private enum Match { case full, partial, none }

    private var pending: [Character] = []  // held-back text that may be a tag start
    private var content = ""  // text collected inside the current tag
    private var inTag = false
    private var lastSpoken: Character?
    private var afterTag = false  // a tag was just removed, so collapse doubled spaces
    /// Where each item of the last `feed` or `flush` sat in its spoken text, in characters, so the screen can put it back.
    public private(set) var offsets: [Int] = []

    public init() {}

    public mutating func feed(_ delta: String) -> Output {
        pending += Array(delta)
        offsets = []
        var out = Output()
        var i = 0
        scan: while i < pending.count {
            let tag = inTag ? Self.close : Self.open
            guard let lt = pending[i...].firstIndex(of: "<") else {
                take(pending[i...], into: &out)
                i = pending.count
                break
            }
            take(pending[i..<lt], into: &out)
            i = lt
            switch Self.match(pending[lt...], tag) {
            case .partial:
                break scan  // may still become a tag; wait for more text
            case .full:
                i = lt + tag.count
                if inTag {
                    let item = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !item.isEmpty {
                        out.shown.append(item)
                        offsets.append(out.spoken.count)
                    }
                    content = ""
                    afterTag = true
                }
                inTag.toggle()
            case .none:
                take(pending[lt...(lt)], into: &out)
                i = lt + 1
            }
        }
        pending.removeFirst(i)
        return out
    }

    public mutating func flush() -> Output {
        var out = Output()
        var marks: [Int] = []
        if inTag {
            // Forgotten close tag: show the content, never speak it.
            let item = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !item.isEmpty {
                out.shown.append(item)
                marks.append(0)
            }
        } else {
            take(pending[...], into: &out)
        }
        self = ShowFilter()
        offsets = marks
        return out
    }

    private static func isWord(_ c: Character) -> Bool { c.isLetter || c.isNumber }

    private static func match(_ text: ArraySlice<Character>, _ tag: [Character]) -> Match {
        let head = text.prefix(tag.count).map { Character($0.lowercased()) }
        guard head == Array(tag.prefix(head.count)) else { return .none }
        return head.count == tag.count ? .full : .partial
    }

    private mutating func take(_ text: ArraySlice<Character>, into out: inout Output) {
        guard !text.isEmpty else { return }
        if inTag {
            content += String(text)
            return
        }
        var text = text
        if afterTag, lastSpoken == " ", text.first == " " { text = text.dropFirst() }
        guard !text.isEmpty else { return }
        // "the file<show>x</show>and" would be heard as "fileand".
        if afterTag, let last = lastSpoken, let first = text.first, Self.isWord(last), Self.isWord(first) {
            out.spoken += " "
        }
        out.spoken += String(text)
        lastSpoken = text.last
        afterTag = false
    }
}

import Foundation

extension ShowFilter {
    /// A reply to read rather than hear, as Markdown: each `<show>` item is inline code, or a link when it's a URL.
    public static func markdown(_ text: String) -> String {
        text.replacing(tag) { match in
            let item = String(match.output[1].substring ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if item.isEmpty { return "" }
            if item.hasPrefix("https://") || item.hasPrefix("http://") { return "[\(item)](\(item))" }
            // A double fence keeps a backtick inside the item from ending the code span.
            return item.contains("`") ? "`` \(item) ``" : "`\(item)`"
        }
    }

    // A tag still streaming in has no close yet; it shows as code until it's done.
    nonisolated(unsafe) private static let tag = try! Regex("(?is)<show>(.*?)(?:</show>|$)")
}
