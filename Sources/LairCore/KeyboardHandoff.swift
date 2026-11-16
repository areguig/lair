import Foundation

/// Going on with a call in the agent's own CLI, in a terminal, and back to voice when the CLI quits.
public enum KeyboardHandoff {
    /// Where the CLI opens: Terminal comes with macOS; herdr when you have it and chose it.
    public enum Terminal: String, Codable, Sendable, CaseIterable {
        case terminal, herdr
    }

    /// The CLI line that picks the session up; nil for agents whose CLI isn't known to share its sessions with ACP.
    public static func command(preset: String?, sessionID: String) -> [String]? {
        switch preset {
        case "claude": ["claude", "--resume", sessionID]
        case "codex": ["codex", "resume", sessionID]
        default: nil
        }
    }

    /// Who comes back to voice: opened as `lair://back?agent=…&session=…` when the CLI quits.
    public struct Back: Equatable, Sendable {
        public let agent: String
        public let sessionID: String

        public init(agent: String, sessionID: String) {
            (self.agent, self.sessionID) = (agent, sessionID)
        }

        public var url: URL {
            var components = URLComponents()
            components.scheme = "lair"
            components.host = "back"
            components.queryItems = [.init(name: "agent", value: agent), .init(name: "session", value: sessionID)]
            return components.url!
        }

        public init?(url: URL) {
            guard url.scheme == "lair", url.host() == "back",
                  let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                  let agent = items.first(where: { $0.name == "agent" })?.value,
                  let session = items.first(where: { $0.name == "session" })?.value
            else { return nil }
            (self.agent, self.sessionID) = (agent, session)
        }
    }

    /// What the terminal runs: the CLI in the agent's folder with your login PATH. Quitting it, or closing the
    /// window, opens `back`; in herdr the pane then closes itself, so the Lair tab holds only agents at the keyboard.
    public static func script(command: [String], folder: String, path: String?, back: Back) -> String {
        var lines = [
            "#!/bin/sh",
            "# Lair: quitting the CLI gives the conversation back to Lair's voice.",
            "back=\(quote(back.url.absoluteString))",
            #"trap '/usr/bin/open -g "$back"; [ -z "$HC_TERMINAL_ID" ] || hc kill "$HC_TERMINAL_ID" >/dev/null 2>&1' EXIT"#,
            "trap 'exit' HUP INT TERM",
        ]
        if let path { lines.append("export PATH=\(quote(path))") }
        lines.append("cd \(quote(folder)) || exit 1")
        lines.append(command.map(quote).joined(separator: " "))
        return lines.joined(separator: "\n") + "\n"
    }

    /// Opens the script at `file` in Terminal.
    public static func terminalLaunch(_ file: URL) -> [String] {
        ["/usr/bin/open", "-a", "Terminal", file.path]
    }

    /// herdr's space for agents at the keyboard, all in one tab; it goes away with its last pane.
    public static let herdrSpace = "Lair"

    /// Lists herdr's spaces, tabs and panes, for `herdrLaunch`.
    public static let herdrList = ["/usr/bin/env", "herdr-app", "ls"]

    /// Opens the script at `file` in herdr: beside the agents already in the Lair space, else as that space.
    /// `list` is what `herdrList` printed.
    public static func herdrLaunch(_ file: URL, folder: String, list: Data) -> [String] {
        let argv = ["/bin/sh", file.path]
        if let pane = lairPane(in: list) {
            return herdr("pane.split", ["direction": "right", "pane": pane, "argv": argv])
        }
        return herdr("space.new", ["name": herdrSpace, "tab": "Agents", "folder": folder, "argv": argv])
    }

    /// The last pane of the Lair space's first tab.
    private static func lairPane(in list: Data) -> String? {
        struct List: Decodable {
            let spaces: [Space]
            struct Space: Decodable { let name: String?; let tabs: [Tab] }
            struct Tab: Decodable { let terminals: [Pane] }
            struct Pane: Decodable { let pane: String? }
        }
        let space = (try? JSONDecoder().decode(List.self, from: list))?.spaces.first { $0.name == herdrSpace }
        return space?.tabs.first?.terminals.last?.pane
    }

    private static func herdr(_ command: String, _ arguments: [String: Any]) -> [String] {
        let data = try! JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys, .withoutEscapingSlashes])
        return ["/usr/bin/env", "herdr-app", "do", command, String(decoding: data, as: UTF8.self)]
    }

    static func quote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
