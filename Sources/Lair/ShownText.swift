import AppKit
import LairCore
import SwiftUI

/// An agent's line with the links, paths and commands it showed put back in the sentence, clickable.
enum ShownText {
    static func attributed(_ line: Call.Line) -> AttributedString {
        var out = AttributedString()
        for segment in Shown.segments(of: line.text, line.shown) {
            switch segment {
            case .text(let text): out += AttributedString(text)
            case .item(let item): out += styled(item)
            }
        }
        return out
    }

    private static func styled(_ item: Shown) -> AttributedString {
        var text = AttributedString(item.label())
        text.link = url(for: item)
        switch item.target {
        case .link, .path:
            text.underlineStyle = .single
        case .command:
            text.font = .system(.callout, design: .monospaced)
            text.backgroundColor = Color.primary.opacity(0.1)
        }
        return text
    }

    /// A link as it is, a path as a file URL, a command as a Lair URL that copies it.
    private static func url(for item: Shown) -> URL? {
        switch item.target {
        case .link(let url): return url
        case .path(let path): return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        case .command:
            var parts = URLComponents()
            parts.scheme = copyScheme
            parts.host = "copy"
            parts.queryItems = [URLQueryItem(name: "text", value: item.item)]
            return parts.url
        }
    }

    private static let copyScheme = "lair-copy"

    /// Web links open in the browser, a path shows in Finder (or is copied if it isn't there), a command is copied.
    static func open(_ url: URL) -> OpenURLAction.Result {
        if url.scheme == copyScheme {
            copy(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value ?? "")
        } else if url.isFileURL {
            if FileManager.default.fileExists(atPath: url.path) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } else {
                copy(url.path)
            }
        } else {
            NSWorkspace.shared.open(url)
        }
        return .handled
    }

    private static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
