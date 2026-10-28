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
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            Snapshot.write(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
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
            MenuBarIcon(state: room.focused?.state ?? .offline)
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
        let call = room.calls[0]
        call.state = .speaking
        call.lines = [
            .init(role: .you, text: "What's left on the release checklist?"),
            .init(role: .agent, text: "Two things: the changelog still needs the new voice section, and the build "
                + "number hasn't been bumped yet. Want me to do both?"),
        ]
        let renderer = ImageRenderer(content: RoomView(room: room))
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return }
        try? png.write(to: url)
    }
}
