import Foundation

/// Going on with a call in the agent's own CLI, in a terminal; Lair takes it back once that CLI is gone.
public enum KeyboardHandoff {
    /// Where the CLI opens: Terminal comes with macOS; the others when you have them and chose one.
    public enum Terminal: String, Codable, Sendable, CaseIterable {
        case terminal, iterm, ghostty, herdr

        public var name: String {
            switch self {
            case .terminal: "Terminal"
            case .iterm: "iTerm2"
            case .ghostty: "Ghostty"
            case .herdr: "herdr"
            }
        }

        /// How macOS finds the app, to tell whether it's installed.
        public var bundleID: String {
            switch self {
            case .terminal: "com.apple.Terminal"
            case .iterm: "com.googlecode.iterm2"
            case .ghostty: "com.mitchellh.ghostty"
            case .herdr: "dev.herdr.app"
            }
        }
    }

    /// The CLI line that picks the session up; nil for agents whose CLI isn't known to share its sessions with ACP.
    public static func command(preset: String?, sessionID: String) -> [String]? {
        switch preset {
        case "claude": ["claude", "--resume", sessionID]
        // The shared daemon keeps the session after the CLI quits, so Lair couldn't pick it up again.
        case "codex": ["codex", "resume", "--no-daemon", sessionID]
        default: nil
        }
    }

    /// What the terminal runs: the CLI in the agent's folder with your login PATH. In herdr the pane closes once the CLI
    /// quits, so the Lair tab holds only agents at the keyboard.
    public static func script(command: [String], folder: String, path: String?) -> String {
        var lines = [
            "#!/bin/sh",
            "# Lair: once this CLI quits, Lair picks the conversation up again by voice.",
            #"trap '[ -z "$HC_TERMINAL_ID" ] || hc kill "$HC_TERMINAL_ID" >/dev/null 2>&1' EXIT"#,
            "trap 'exit' HUP INT TERM",
        ]
        if let path { lines.append("export PATH=\(quote(path))") }
        lines.append("cd \(quote(folder)) || exit 1")
        lines.append(command.map(quote).joined(separator: " "))
        return lines.joined(separator: "\n") + "\n"
    }

    /// Opens the script at `file` in a new window of `terminal`; herdr places it with `herdrLaunch` instead.
    public static func windowLaunch(_ file: URL, in terminal: Terminal) -> [String] {
        switch terminal {
        case .terminal, .herdr: ["/usr/bin/open", "-a", "Terminal", file.path]
        case .iterm: ["/usr/bin/open", "-a", "iTerm", file.path]
        case .ghostty: ["/usr/bin/open", "-na", "Ghostty", "--args", "-e", "/bin/sh", file.path]
        }
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
