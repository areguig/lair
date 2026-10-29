// Lair: a menu-bar room where you call your agents and talk to them by voice.
import KeyboardShortcuts
import LairCore
import LairMCP
import SwiftUI

extension KeyboardShortcuts.Name {
    static let pushToTalk = Self("pushToTalk", initial: .init(.space, modifiers: [.option]))
}

/// The talk shortcut as shown in the panel and Mission Control, kept current when it's changed in Settings.
@Observable @MainActor final class TalkKey {
    static let shared = TalkKey()
    private(set) var label = TalkKey.current

    private init() {
        // KeyboardShortcuts posts this on every change; the name isn't public.
        NotificationCenter.default.addObserver(forName: .init("KeyboardShortcuts_shortcutByNameDidChange"), object: nil,
                                               queue: .main) { _ in
            MainActor.assumeIsolated { TalkKey.shared.label = TalkKey.current }
        }
    }

    private static var current: String? { KeyboardShortcuts.getShortcut(for: .pushToTalk)?.description }
}

@main
struct LairApp: App {
    private let room: Room
    private let link: GuestLink
    private let store: ConfigStore
    private let orb: FloatingOrb

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
        if let i = CommandLine.arguments.firstIndex(of: "--demo-frame"), i + 2 < CommandLine.arguments.count,
           let seconds = Double(CommandLine.arguments[i + 1]) {
            let url = URL(fileURLWithPath: CommandLine.arguments[i + 2])
            Task { @MainActor in
                do {
                    try await Demo.writeFrame(at: seconds, to: url)
                    exit(0)
                } catch {
                    print("Demo frame failed: \(error)")
                    exit(1)
                }
            }
            RunLoop.main.run()
        }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            let variant = i + 2 < CommandLine.arguments.count ? CommandLine.arguments[i + 2] : "approval"
            Snapshot.write(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]), variant: variant)
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--mission-snapshot"), i + 1 < CommandLine.arguments.count {
            Snapshot.writeMissionControl(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--settings-snapshot"), i + 1 < CommandLine.arguments.count {
            let agent = i + 2 < CommandLine.arguments.count ? CommandLine.arguments[i + 2] : nil
            Snapshot.writeSettings(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]), agent: agent)
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--icon"), i + 1 < CommandLine.arguments.count {
            Snapshot.writeIcon(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
            exit(0)
        }
        let store = ConfigStore()
        let room = Room(config: store.config)
        let link = GuestLink(room: room)
        link.apply(store.config.guests)
        store.onChange = {
            room.apply($0)
            link.apply($0.guests)
        }
        store.watch()
        self.store = store
        self.room = room
        self.link = link
        orb = FloatingOrb(room: room)
        KeyboardShortcuts.onKeyDown(for: .pushToTalk) { room.pressTalk() }
        KeyboardShortcuts.onKeyUp(for: .pushToTalk) { room.releaseTalk() }
        KeyboardShortcuts.onKeyDown(for: .missionControl) { MissionControl.toggle(room: room) }
        Task { await room.start() }
    }

    var body: some Scene {
        MenuBarExtra {
            RoomView(room: room, configProblem: store.problem)
        } label: {
            MenuBarIcon(room: room)
        }
        .menuBarExtraStyle(.window)

        Window(SettingsView.title, id: SettingsView.id) {
            SettingsView(store: store, room: room, link: link)
        }
        .windowResizability(.contentSize)
    }
}

/// The whole room at a glance: what needs you first, then what's happening, then whether anyone is on a call.
struct MenuBarIcon: View {
    let room: Room

    var body: some View {
        let (symbol, label) = summary
        Image(systemName: symbol)
            .symbolRenderingMode(.hierarchical)
            .accessibilityLabel("Lair, \(label)")
    }

    private var summary: (String, String) {
        switch room.readiness {
        case .loading: return ("circle.dotted", "getting ready")
        case .microphoneDenied, .failed: return ("exclamationmark.circle", "needs attention")
        case .ready: break
        }
        let calls = room.calls
        if let waiting = calls.first(where: { $0.state == .waiting }) {
            return ("hand.raised.circle.fill", "\(waiting.agent.name) needs your OK")
        }
        if let active = calls.first(where: { $0.state == .listening || $0.state == .speaking }) {
            return ("waveform.circle.fill", "\(active.agent.name) is \(active.state == .listening ? "listening" : "speaking")")
        }
        if let working = calls.first(where: { $0.state == .thinking }) {
            return ("ellipsis.circle.fill", "\(working.agent.name) is working")
        }
        if let news = calls.first(where: \.unread) { return ("circle.circle.fill", "\(news.agent.name) has news") }
        if calls.contains(where: \.inCall) { return ("circle.circle.fill", "in a call") }
        return ("circle.circle", "idle")
    }
}

/// `Lair --snapshot out.png [approval|chat|reply|empty|micdenied|crowded]` renders the panel in a demo state,
/// to check the design without clicking around.
@MainActor enum Snapshot {
    static func write(to url: URL, variant: String = "approval") {
        let agents = variant == "empty" ? [] : variant == "crowded"
            ? (1...6).map { AgentConfig(id: "a\($0)", name: ["Claude", "Echo", "Nova", "Research assistant", "Ops", "Docs"][$0 - 1],
                                        kind: .claudeCode, voice: "af_heart", color: AgentConfig.palette[$0 - 1]) }
            : [AgentConfig(id: "claude", name: "Claude", kind: .claudeCode, voice: "af_heart", color: "#D97757", directory: "~"),
               AgentConfig(id: "echo", name: "Echo", kind: .hermes, voice: "bf_emma", color: "#7B5CFF")]
        let room = Room(config: LairConfig(agents: agents))
        room.readiness = variant == "micdenied" ? .microphoneDenied : .ready
        if let call = room.calls.first {
            call.details = "claude-haiku-5-5"
            call.lines = [
                .init(role: .you, text: "What's left on the release checklist?"),
                .init(role: .agent, text: "Two things: the changelog still needs the new voice section, and the build "
                    + "number hasn't been bumped yet. Want me to do both?"),
            ]
            switch variant {
            case "approval":
                room.calls[1].state = .thinking
                room.calls[1].unread = true
                call.state = .waiting
                call.pendingApproval = ApprovalRequest(
                    id: "demo", tool: "Bash", summary: "Bump the build number in Info.plist and commit it",
                    suggestions: Data(#"[{"type":"addRules","rules":[{"toolName":"Bash"}],"behavior":"allow","destination":"localSettings"}]"#.utf8))
            case "chat":
                call.state = .speaking
                call.lines += [
                    .init(role: .you, text: "Yes, go ahead."),
                    .init(role: .info, text: "Always allowed: Bump the build number in Info.plist and commit it"),
                    .init(role: .agent, text: "Done. The changelog is updated and the build number is bumped.",
                          shown: ["~/dev/app/CHANGELOG.md", "https://github.com/example/app/pull/42"]),
                ]
                room.calls[1].lines = [.init(role: .problem, text: "Echo needs an API key. Add it in Settings › Agents.",
                                             action: .openSettings)]
            case "reply":
                call.state = .listening
                room.answering = .init(callID: call.id, since: .now)
            case "crowded":
                call.state = .ready
                room.calls[3].state = .thinking
                room.calls[4].state = .waiting
            case "guest", "guestspeaks":
                call.state = .thinking
                if variant == "guest" {
                    room.calls[1].state = .waiting
                    room.calls[1].pendingApproval = ApprovalRequest(id: "echo", tool: "Bash", summary: "Restart the staging server")
                }
                let guest = room.call(for: Guest(id: "demo", name: "Claude Code",
                                                 folder: URL(fileURLWithPath: "/Users/me/dev/lair")))
                guest.lines = [.init(role: .agent, text: "The migration ran on staging; all 412 tests pass.")]
                if variant == "guest" {
                    let question = "Ship it to production now, or wait for the morning?"
                    guest.questionText = question
                    guest.questionSince = .now - 34
                    guest.questionDeadline = .now + 86
                    guest.state = .waiting
                } else {
                    guest.state = .speaking
                }
                room.focus(guest)
            default:
                break
            }
        }
        let problem = variant == "chat" ? "The config file has an error: line 4 is missing a comma." : nil
        writePNG(RoomView(room: room, configProblem: problem).environment(\.renderTime, 0), scale: 2, to: url)
    }

    /// Mission Control with a demo exchange, drawn in a hidden window so scroll views render.
    static func writeMissionControl(to url: URL) {
        let room = Room(config: LairConfig(agents: Array(Demo.agents.prefix(2))))
        room.readiness = .ready
        let claude = room.calls[0]
        claude.state = .speaking
        claude.details = "claude-haiku-5-5"
        claude.log(.you("What's left before we ship the release?"))
        claude.record(.thinking("The user wants the release status. I should check the changelog and the build number "
            + "before answering, and look at the open TODOs."))
        claude.record(.toolStarted(id: "t1", name: "Bash", input: "git log --oneline -5"))
        claude.record(.toolFinished(id: "t1", output: "b68c50f Settings footer\n410f237 Model picker\n08c8726 Voice switch",
                                 failed: false))
        claude.record(.toolStarted(id: "t2", name: "Edit", input: "~/dev/app/CHANGELOG.md"))
        claude.record(.toolFinished(id: "t2", output: "@@ -1,3 +1,4 @@\n # Changelog\n+- Voice: switch model by voice\n- WIP",
                                 failed: false))
        claude.record(.toolStarted(id: "t3", name: "Bash", input: "swift test"))
        claude.logText("Two things are left: <show>CHANGELOG.md</show> needed the voice section, which I just added, and the "
            + "build number. Tests are running now.")
        claude.record(.usage(inputTokens: 18_400, outputTokens: 512, cost: 0.0213))
        claude.log(.timing(heard: 140, firstWord: 1_880, firstSound: 2_410, total: 6_120))
        let echo = room.calls[1]
        echo.state = .thinking
        echo.log(.you("did last night's backups finish?"))
        echo.record(.toolStarted(id: "c1", name: "delegate_task", input: ""))
        echo.logText("I've started the check in the background; we can keep talking.")
        echo.log(.note("Background task finished"))
        echo.logText("Yes. All three finished, and the newest one is from three this morning.")
        echo.log(.approval("Delete backups older than 30 days"))
        echo.state = .waiting
        echo.pendingApproval = ApprovalRequest(id: "demo", tool: "terminal", summary: "Delete backups older than 30 days")
        let view = NSHostingView(rootView: MissionControl(room: room))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 780), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// The settings window with demo agents, drawn in a hidden window so native controls render.
    static func writeSettings(to url: URL, agent: String? = nil) {
        let file = FileManager.default.temporaryDirectory.appending(path: "lair-settings-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        var config = LairConfig(agents: Demo.agents)
        if agent == "mac" { config.guests = .standard }
        try? config.save(to: file)
        let store = ConfigStore(url: file)
        let room = Room(config: store.config)
        let link = GuestLink(room: room)
        link.status = config.guests.map { .on($0.url) } ?? .off
        SettingsRoute.shared.tab = agent == "mac" ? .mac : .agents
        let view = NSHostingView(rootView: SettingsView(store: store, room: room, link: link, selectedAgent: agent))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 500), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
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
