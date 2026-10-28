// Lair: a menu-bar room where you call your agents and talk to them by voice.
import KeyboardShortcuts
import LairCore
import SwiftUI

extension KeyboardShortcuts.Name {
    static let pushToTalk = Self("pushToTalk", initial: .init(.space, modifiers: [.option]))
}

@main
struct LairApp: App {
    private let room: Room

    init() {
        // An agent process that exits must not take Lair down with it: writing to it then just throws.
        signal(SIGPIPE, SIG_IGN)
        if let i = CommandLine.arguments.firstIndex(of: "--demo"), i + 1 < CommandLine.arguments.count {
            let folder = URL(fileURLWithPath: CommandLine.arguments[i + 1])
            Task { @MainActor in
                do {
                    try await Demo.run(into: folder)
                    exit(0)
                } catch {
                    print("Demo failed: \(error)")
                    exit(1)
                }
            }
            // The demo's tasks run on the main queue; keep it turning instead of starting the app.
            RunLoop.main.run()
        }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            Snapshot.write(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--icon"), i + 1 < CommandLine.arguments.count {
            Snapshot.writeIcon(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
            exit(0)
        }
        let config: LairConfig
        do {
            config = try LairConfig.load()
        } catch {
            config = .initial
            NSLog("Lair: couldn't read \(LairConfig.defaultURL.path), using defaults: \(error)")
        }
        let room = Room(config: config)
        self.room = room
        KeyboardShortcuts.onKeyDown(for: .pushToTalk) { room.pressTalk() }
        KeyboardShortcuts.onKeyUp(for: .pushToTalk) { room.releaseTalk() }
        Task { await room.start() }
    }

    var body: some Scene {
        MenuBarExtra {
            RoomView(room: room)
        } label: {
            MenuBarIcon(state: room.calls.contains { $0.state == .waiting } ? .waiting : room.focused?.state ?? .offline)
        }
        .menuBarExtraStyle(.window)

        Window("Push-to-Talk Shortcut", id: ShortcutWindow.id) {
            ShortcutWindow()
        }
        .windowResizability(.contentSize)
    }
}

struct ShortcutWindow: View {
    static let id = "shortcut"

    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Hold to talk:", name: .pushToTalk)
        }
        .padding(20)
        .frame(width: 320)
    }
}

struct MenuBarIcon: View {
    let state: Call.State

    var body: some View {
        Image(systemName: symbol)
            .symbolRenderingMode(.hierarchical)
            .accessibilityLabel("Lair")
    }

    private var symbol: String {
        switch state {
        case .offline: "circle.circle"
        case .ready: "circle.circle.fill"
        case .listening, .speaking: "waveform.circle.fill"
        case .thinking: "ellipsis.circle.fill"
        case .waiting: "hand.raised.circle.fill"
        }
    }
}

/// `Lair --snapshot out.png` renders the panel with a demo call, to check the design without clicking around.
@MainActor enum Snapshot {
    static func write(to url: URL) {
        let room = Room(config: LairConfig(agents: [
            AgentConfig(id: "claude", name: "Claude", kind: .claudeCode, voice: "af_heart", color: "#D97757", directory: "~"),
            AgentConfig(id: "sage", name: "Sage", kind: .claudeCode, voice: "bf_emma", color: "#6C8CFF"),
        ]))
        room.readiness = .ready
        room.calls[1].state = .thinking
        room.calls[1].unread = true
        let call = room.calls[0]
        call.state = .waiting
        call.details = "claude-haiku-5-5"
        call.pendingApproval = ApprovalRequest(id: "demo", tool: "Bash",
                                               summary: "Bump the build number in Info.plist and commit it",
                                               suggestions: Data(#"[{"type":"addRules","rules":[{"toolName":"Bash"}],"behavior":"allow","destination":"localSettings"}]"#.utf8))
        call.lines = [
            .init(role: .you, text: "What's left on the release checklist?"),
            .init(role: .agent, text: "Two things: the changelog still needs the new voice section, and the build "
                + "number hasn't been bumped yet. Want me to do both?"),
        ]
        writePNG(RoomView(room: room), scale: 2, to: url)
    }

    /// `Lair --icon out.png`: the 1024px app icon, drawn from the orb.
    static func writeIcon(to url: URL) {
        writePNG(AppIcon(), scale: 1, to: url)
    }

    private static func writePNG(_ view: some View, scale: Double, to url: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return }
        try? png.write(to: url)
    }
}

/// A dark rounded square on the Big Sur grid (824pt in a 1024pt canvas) with a big glowing orb.
struct AppIcon: View {
    private let color = Color(red: 0.851, green: 0.467, blue: 0.341).mix(with: Color(red: 0.482, green: 0.361, blue: 1), by: 0.12)

    var body: some View {
        ZStack {
            Color(red: 0.055, green: 0.06, blue: 0.075)
            RadialGradient(colors: [color.opacity(0.45), .clear], center: .center, startRadius: 0, endRadius: 420)
            Orb(color: color, state: .ready)
                .frame(width: 560, height: 560)
        }
        .frame(width: 824, height: 824)
        .clipShape(RoundedRectangle(cornerRadius: 185, style: .continuous))
        .frame(width: 1024, height: 1024)
    }
}
