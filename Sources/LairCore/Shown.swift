import Foundation

/// Something the agent showed instead of saying, with where it sat in its line, so the screen can put it back in the sentence.
public struct Shown: Equatable, Sendable {
    /// What the item opens: a link in the browser, a path in Finder, or a command to copy.
    public enum Target: Equatable, Sendable {
        case link(URL)
        case path(String)
        case command
    }

    /// The raw item as the agent wrote it.
    public let item: String
    /// Characters into the line's text.
    public let at: Int

    public init(item: String, at: Int) {
        self.item = item
        self.at = at
    }

    /// A line's text cut where the items sit, in reading order.
    public enum Segment: Equatable, Sendable {
        case text(String)
        case item(Shown)
    }

    /// The text and the items in the order to read them; an offset past the end lands at the end. The voice's text loses
    /// the space beside a removed item, so a word touching an item gets one back for the eye.
    public static func segments(of text: String, _ shown: [Shown]) -> [Segment] {
        var out = cut(text, shown)
        for i in out.indices {
            guard case .text(let words) = out[i] else { continue }
            let before = i > 0 && words.first.map { $0.isLetter || $0.isNumber } == true
            let after = i + 1 < out.count && words.last.map { $0.isLetter || $0.isNumber } == true
            out[i] = .text((before ? " " : "") + words + (after ? " " : ""))
        }
        return out
    }

    private static func cut(_ text: String, _ shown: [Shown]) -> [Segment] {
        var out: [Segment] = []
        var from = text.startIndex
        for item in shown.sorted(by: { $0.at < $1.at }) {
            let to = text.index(text.startIndex, offsetBy: item.at, limitedBy: text.endIndex) ?? text.endIndex
            if to > from { out.append(.text(String(text[from..<to]))) }
            out.append(.item(item))
            from = max(from, to)
        }
        if from < text.endIndex { out.append(.text(String(text[from...]))) }
        return out
    }

    /// Items with their offsets, which the filter reports in step.
    static func list(_ items: [String], at offsets: [Int]) -> [Shown] {
        zip(items, offsets).map { Shown(item: $0, at: $1) }
    }

    /// The pieces of a streamed delta, moved to where they sit in the line so far.
    public static func place(_ piece: SpokenStream.Piece, after text: String) -> [Shown] {
        piece.placed.map { Shown(item: $0.item, at: text.count + $0.at) }
    }

    /// A markdown link `[title](https://…)` is its title, a bare URL its site, a path its last parts; a command stays as is.
    public func label(home: String = NSHomeDirectory()) -> String {
        if let link = Self.markdownLink(item) { return link.title }
        switch target {
        case .link(let url): return Self.site(of: url)
        case .path(let path): return Self.abbreviated(path, home: home)
        case .command: return item
        }
    }

    public var target: Target {
        if let link = Self.markdownLink(item) { return .link(link.url) }
        if let url = Self.web(item) { return .link(url) }
        if (item.hasPrefix("/") || item.hasPrefix("~")), !item.contains("\n") { return .path(item) }
        return .command
    }

    private static func web(_ text: String) -> URL? {
        guard let url = URL(string: text), ["http", "https"].contains(url.scheme ?? ""), url.host != nil else { return nil }
        return url
    }

    private static func markdownLink(_ text: String) -> (title: String, url: URL)? {
        guard let match = text.wholeMatch(of: /\[([^\]]+)\]\(([^)\s]+)\)/), let url = web(String(match.2)) else { return nil }
        return (String(match.1), url)
    }

    private static func site(of url: URL) -> String {
        let host = url.host ?? url.absoluteString
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// `~` for home; a long path keeps its last two parts after "…/".
    static func abbreviated(_ path: String, home: String) -> String {
        var path = path
        if path == home || path.hasPrefix(home + "/") { path = "~" + path.dropFirst(home.count) }
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let named = parts.first == "~" ? Array(parts.dropFirst()) : parts
        guard named.count > 2 else { return path }
        return "…/" + named.suffix(2).joined(separator: "/")
    }
}
