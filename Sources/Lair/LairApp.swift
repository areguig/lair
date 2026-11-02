// Lair: a menu-bar room where you call your agents and talk to them by voice.
import KeyboardShortcuts
import LairCore
import LairMCP
import LairVoice
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
    private let island: Island
    private let updates: Updates
    private let registry: RegistryStore

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
            let appearance = i + 3 < CommandLine.arguments.count ? CommandLine.arguments[i + 3] : "dark"
            Snapshot.write(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]), variant: variant, appearance: appearance)
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--island-snapshot"), i + 1 < CommandLine.arguments.count {
            let variant = i + 2 < CommandLine.arguments.count ? CommandLine.arguments[i + 2] : "asking"
            Snapshot.writeIsland(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]), variant: variant)
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--mission-snapshot"), i + 1 < CommandLine.arguments.count {
            let look = i + 2 < CommandLine.arguments.count ? CommandLine.arguments[i + 2] : nil
            Snapshot.writeMissionControl(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]), look: look)
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--settings-snapshot"), i + 1 < CommandLine.arguments.count {
            let agent = i + 2 < CommandLine.arguments.count ? CommandLine.arguments[i + 2] : nil
            Snapshot.writeSettings(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]), agent: agent)
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--welcome-snapshot"), i + 1 < CommandLine.arguments.count {
            let variant = i + 2 < CommandLine.arguments.count ? CommandLine.arguments[i + 2] : "loading"
            let appearance = i + 3 < CommandLine.arguments.count ? CommandLine.arguments[i + 3] : "dark"
            Snapshot.writeWelcome(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]), variant: variant, appearance: appearance)
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--icon"), i + 1 < CommandLine.arguments.count {
            Snapshot.writeIcon(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
            exit(0)
        }
        let store = ConfigStore()
        let room = Room(config: store.config)
        room.saveAgent = { draft in
            var config = store.config
            var agent = draft
            agent.id = config.newAgentID(for: agent.name)
            config.agents.append(agent)
            store.save(config)
            return agent
        }
        room.saveSilent = { on in
            var config = store.config
            config.silent = on ? true : nil
            store.save(config)
        }
        let link = GuestLink(room: room)
        link.apply(store.config.guests)
        let island = Island(room: room)
        island.isOn = store.config.showsIsland
        store.onChange = {
            room.apply($0)
            link.apply($0.guests)
            island.isOn = $0.showsIsland
        }
        store.watch()
        self.store = store
        self.room = room
        self.link = link
        self.island = island
        let registry = RegistryStore()
        self.registry = registry
        updates = Updates()
        KeyboardShortcuts.onKeyDown(for: .pushToTalk) { room.pressTalk() }
        KeyboardShortcuts.onKeyUp(for: .pushToTalk) { room.releaseTalk() }
        KeyboardShortcuts.onKeyDown(for: .missionControl) { MissionControl.toggle(room: room) }
        Task { await room.start() }
        Task { await registry.refresh() }
    }

    var body: some Scene {
        MenuBarExtra {
            RoomView(room: room, configProblem: store.problem, updates: updates)
        } label: {
            MenuBarIcon(room: room, updates: updates)
                .modifier(OpensWelcome(show: store.isNew))
        }
        .menuBarExtraStyle(.window)

        Window(SettingsView.title, id: SettingsView.id) {
            SettingsView(store: store, room: room, link: link, registry: registry)
                .task { await registry.refresh() }
        }
        .windowResizability(.contentSize)

        Window(WelcomeView.title, id: WelcomeView.id) {
            WelcomeView(store: store, room: room)
        }
        .windowResizability(.contentSize)
    }
}

/// Opens the welcome window as the app starts, when there was no config yet. The menu bar icon is the one view that
/// exists at launch, so it carries the call.
private struct OpensWelcome: ViewModifier {
    let show: Bool
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.task {
            guard show else { return }
            openWindow(id: WelcomeView.id)
            SettingsView.bringForward(titled: WelcomeView.title)
        }
    }
}

/// The whole room at a glance: what needs you first, then what's happening, then whether anyone is on a call.
struct MenuBarIcon: View {
    let room: Room
    var updates: Updates?

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
            return ("waveform.circle.fill", "\(active.agent.name) is \(active.state.label.lowercased())")
        }
        if let working = calls.first(where: { $0.state == .thinking }) {
            return ("ellipsis.circle.fill", "\(working.agent.name) is \(CallState.thinking.label.lowercased())")
        }
        if let version = updates?.reminder.version { return ("arrow.down.circle.fill", "Lair \(version) is ready to install") }
        if let news = calls.first(where: \.unread) { return ("circle.circle.fill", "\(news.agent.name) has news") }
        if calls.contains(where: \.inCall) { return ("circle.circle.fill", "in a call") }
        return ("circle.circle", "idle")
    }
}

/// `Lair --snapshot out.png [approval|chat|reply|empty|micdenied|crowded|busy|silent] [light|dark]` renders the panel in a demo
/// state, to check the design without clicking around.
@MainActor enum Snapshot {
    static func write(to url: URL, variant: String = "approval", appearance: String = "dark") {
        let agents = variant == "empty" ? [] : variant == "busy" ? busyAgents : variant == "crowded"
            ? (1...6).map { AgentConfig(id: "a\($0)", name: ["Claude", "Echo", "Nova", "Research assistant", "Ops", "Docs"][$0 - 1],
                                        preset: .claude, voice: "af_heart", color: AgentConfig.palette[$0 - 1]) }
            : [AgentConfig(id: "claude", name: "Claude", preset: .claude, voice: "af_heart", color: "#D97757", directory: "~"),
               AgentConfig(id: "echo", name: "Echo", kind: .hermes, voice: "bf_emma", color: "#7B5CFF")]
        let room = Room(config: LairConfig(agents: agents))
        room.readiness = variant == "micdenied" ? .microphoneDenied : .ready
        if let call = room.calls.first {
            call.details = "Haiku 5.5"
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
                    id: "demo", tool: "Bash", summary: "Bump the build number in Info.plist and commit it", canAlwaysAllow: true)
            case "chat":
                call.state = .speaking
                call.lines += [
                    .init(role: .you, text: "Yes, go ahead."),
                    .init(role: .info, text: "Always allowed: Bump the build number in Info.plist and commit it"),
                    agentLine("Done. I updated <show>~/dev/app/CHANGELOG.md</show> and bumped the build number. "
                        + "The pull request is <show>https://github.com/example/app/pull/42</show>."),
                ]
                room.calls[1].lines = [.init(role: .problem, text: "Echo needs an API key. Add it in Settings › Agents.",
                                             action: .openSettings)]
            case "busy":
                stageBusy(room, call)
            case "silent":
                room.setSilent(true)
                call.state = .thinking
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
                let guest = room.call(for: Guest(id: "demo", name: "Claude Code", client: "claude-code",
                                                 folder: URL(fileURLWithPath: "/Users/me/dev/lair")))
                guest.lines = [.init(role: .agent, text: "The migration ran on staging; all 412 tests pass.")]
                if variant == "guest" {
                    let question = "Ship it to production now, or wait for the morning?"
                    guest.questionText = question
                    guest.questionChoices = ["Ship it now", "Wait for the morning"]
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
        writePNG(RoomView(room: room, configProblem: problem).environment(\.renderTime, 0)
            .environment(\.colorScheme, appearance == "light" ? .light : .dark), scale: 2, to: url)
    }

    /// An agent's line as the app stores it: the `<show>` items taken out of the text, each with where it sat.
    private static func agentLine(_ reply: String) -> Call.Line {
        var stream = SpokenStream()
        var line = Call.Line(role: .agent, text: "")
        for piece in [stream.feed(reply, after: ""), stream.finish()] {
            line.shown += Shown.place(piece, after: line.text)
            line.text += piece.text
        }
        return line
    }

    /// Eight agents of mixed presets and colors, as a busy day looks.
    private static var busyAgents: [AgentConfig] {
        let palette = AgentConfig.palette
        func agent(_ id: String, _ name: String, _ preset: AgentPreset, _ color: String) -> AgentConfig {
            AgentConfig(id: id, name: name, preset: preset, voice: "af_heart", color: color, directory: "~")
        }
        return [agent("claude", "Claude", .claude, palette[0]), agent("cypher", "Cypher", .claude, palette[1]),
                agent("reno", "Reno", .claude, palette[2]), agent("lair", "Lair", .claude, palette[3]),
                agent("copilot", "Copilot", .copilot, palette[4]), agent("opencode", "opencode", .opencode, palette[5]),
                agent("codex", "Codex", .codex, "#10A37F"), agent("pi", "pi ACP", .omp, "#8E8E93")]
    }

    /// A long exchange with a link in an answer, a guest and a streaming reply: the screenshot that sent the panel back to design.
    private static func stageBusy(_ room: Room, _ call: Call) {
        call.state = .speaking
        call.details = "Haiku 5.5 · Default thinking"
        call.lines = [
            .init(role: .you, text: "Claude, what's the weather like in Lyon this weekend?"),
            agentLine("It looks mild: around 18 degrees on Saturday with some cloud, and a few showers on Sunday "
                + "afternoon. I checked a couple of forecasts and they agree to within a degree, so I'd plan on a light jacket "
                + "for the real current conditions. The source is "
                + "<show>[Predictwind's Paris weather](https://www.predictwind.com/weather/france/paris)</show>."),
            .init(role: .you, text: "Claude, could you tell me the weather in Paris? I'm flying there on Friday and I'd "
                + "like to know whether I should pack an umbrella or just a jacket."),
            .init(role: .info, text: "Allowed once: Fetch the forecast page"),
            .init(role: .agent, text: "Paris is cloudy right now at 12 degrees, with rain expected from the early evening."),
        ]
        let guest = room.call(for: Guest(id: "omp", name: "omp", client: "omp-coding-agent",
                                         folder: URL(fileURLWithPath: "/Users/me/dev/landing-page")))
        guest.state = .thinking
        room.calls[1].state = .thinking
        room.calls[2].unread = true
        room.calls[4].state = .ready
    }

    /// Mission Control with a demo exchange, drawn in a hidden window so scroll views render.
    static func writeMissionControl(to url: URL, look: String? = nil) {
        let room = Room(config: LairConfig(agents: Array(Demo.agents.prefix(2))))
        room.readiness = .ready
        let claude = room.calls[0]
        claude.state = .speaking
        claude.details = "Haiku 5.5"
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
        let guest = room.call(for: Guest(id: "demo", name: "omp", folder: URL(fileURLWithPath: "/Users/me/dev/landing-page")))
        guest.logText("Added a subtitle under the heading.")
        guest.questionText = "Which colour should the subtitle be?"
        guest.questionChoices = ["Red", "Green", "Blue"]
        guest.questionSince = .now - 20
        guest.questionDeadline = .now + 100
        guest.state = .waiting
        let view = NSHostingView(rootView: MissionControl(room: room))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 780), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.contentView = view
        // "light" or "dark"; anything else follows the system.
        window.appearance = look.flatMap { NSAppearance(named: $0 == "light" ? .aqua : .darkAqua) }
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// A few real entries of the ACP Registry, so snapshots need no network.
    private static let registryDemo = try! JSONDecoder().decode(Registry.self, from: Data(##"""
    {"agents":[{"id":"auggie","name":"Auggie CLI","version":"0.36.0","description":"Augment Code's powerful software agent, backed by industry-leading context engine","license":"proprietary","website":"https://www.augmentcode.com/","icon":"https://cdn.agentclientprotocol.com/registry/v1/latest/auggie.svg","distribution":{"npx":{"package":"@augmentcode/auggie@0.36.0","args":["--acp"],"env":{"AUGMENT_DISABLE_AUTO_UPDATE":"1"}}}},{"id":"cline","name":"Cline","version":"3.0.74","description":"Autonomous coding agent CLI - capable of creating/editing files, running commands, using the browser, and more","license":"Apache-2.0","website":"https://cline.bot/cli","icon":"https://cdn.agentclientprotocol.com/registry/v1/latest/cline.svg","distribution":{"npx":{"package":"cline@3.0.74","args":["--acp"]}}},{"id":"codex-acp","name":"Codex","version":"2.5.0","description":"ACP adapter for OpenAI's coding assistant","license":"Apache-2.0","icon":"https://cdn.agentclientprotocol.com/registry/v1/latest/codex-acp.svg","distribution":{"npx":{"package":"@agentclientprotocol/codex-acp@2.5.0"}}},{"id":"fast-agent","name":"fast-agent","version":"0.10.1","description":"Code and build agents with comprehensive multi-provider support","license":"Apache 2.0","website":"https://fast-agent.ai","icon":"https://cdn.agentclientprotocol.com/registry/v1/latest/fast-agent.svg","distribution":{"uvx":{"package":"fast-agent-acp==0.10.1","args":["-x"],"env":{"FAST_AGENT_MODEL":"codexplan"}}}},{"id":"gemini","name":"Gemini CLI","version":"0.66.0","description":"Google's official CLI for Gemini","license":"Apache-2.0","website":"https://geminicli.com","icon":"https://cdn.agentclientprotocol.com/registry/v1/latest/gemini.svg","distribution":{"npx":{"package":"@google/gemini-cli@0.66.0","args":["--acp"]}}},{"id":"github-copilot-cli","name":"Copilot","version":"1.0.105","description":"GitHub's AI pair programmer","license":"proprietary","website":"https://github.com/features/copilot/cli/","icon":"https://cdn.agentclientprotocol.com/registry/v1/latest/github-copilot-cli.svg","distribution":{"npx":{"package":"@github/copilot@1.0.105","args":["--acp"]}}},{"id":"qwen-code","name":"Qwen Code","version":"0.26.5","description":"Alibaba's Qwen coding assistant","license":"Apache-2.0","website":"https://qwenlm.github.io/qwen-code-docs/en/users/overview","icon":"https://cdn.agentclientprotocol.com/registry/v1/latest/qwen-code.svg","distribution":{"npx":{"package":"@qwen-code/qwen-code@0.26.5","args":["--acp","--experimental-skills"]}}}]}
    """##.utf8))

    /// The settings window with demo agents, drawn in a hidden window so native controls render.
    static func writeSettings(to url: URL, agent: String? = nil) {
        let file = FileManager.default.temporaryDirectory.appending(path: "lair-settings-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        var hermes = AgentConfig(id: "hermes", name: "Hermes", kind: .hermes, voice: "am_adam", color: "#4BA3E3")
        hermes.url = "http://hermes.local:8642"
        hermes.model = "hermes-agent"
        hermes.headers = ["X-Access-Token"]
        var config = LairConfig(agents: Demo.agents + [hermes])
        if agent == "mac" { config.guests = .standard }
        if agent == "general" { config.sounds = SoundSettings(volume: 0.7, off: [.done]) }
        if agent == "update" {
            var pinned = config.newAgent(named: "Auggie CLI", voices: VoiceModels.voices)
            pinned.follow(registryDemo.entry(id: "auggie")!)
            pinned.command = ["npx", "-y", "@augmentcode/auggie@0.35.0", "--acp"]
            pinned.directory = "~"
            config.agents.append(pinned)
        }
        try? config.save(to: file)
        let store = ConfigStore(url: file)
        let room = Room(config: store.config)
        let link = GuestLink(room: room)
        link.status = config.guests.map { .on($0.url) } ?? .off
        SettingsRoute.shared.tab = agent == "mac" ? .mac : agent == "general" ? .general : .agents
        // An agent id, or a preset name for the first demo agent that uses it.
        let selected = config.agents.first { $0.id == agent || $0.preset == agent }?.id
            ?? (agent == "update" ? config.agents.last?.id : nil)
        let registry = RegistryStore(registry: registryDemo)
        // A folder holding `npx` stands in for the login shell's PATH: Node.js is installed, uv isn't.
        let programs = file.deletingLastPathComponent().appending(path: "lair-settings-bin-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: programs) }
        try? FileManager.default.createDirectory(at: programs, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: programs.appending(path: "npx").path, contents: Data(),
                                       attributes: [.posixPermissions: 0o755])
        room.environment = ["PATH": programs.path]
        let settings = SettingsView(store: store, room: room, link: link, registry: registry, selectedAgent: selected)
        // The "More agents…" sheet's content alone, as a sheet isn't part of the window's view.
        let view = NSHostingView(rootView: agent == "registry"
            ? AnyView(RegistrySheet(store: registry, room: room, added: ["cline"], add: { _ in }).background(Color(nsColor: .windowBackgroundColor)))
            : AnyView(settings))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 500), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        // The General tab is taller than the window: show its end, where the Sounds are.
        if agent == "general", let scroll = view.firstDescendant(ofType: NSScrollView.self), let page = scroll.documentView {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, page.frame.height - scroll.contentView.bounds.height)))
            scroll.reflectScrolledClipView(scroll.contentView)
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// The island under a strip of menu bar, in one of its states: resting, live, listening, asking, approving, or any
    /// of them followed by "-flat" for a screen without a notch.
    static func writeIsland(to url: URL, variant: String) {
        var sage = Demo.agents[2]
        sage.directory = "/Users/me/dev/landing-page"
        let room = Room(config: LairConfig(agents: Array(Demo.agents.prefix(2)) + [sage]))
        room.readiness = .ready
        let claude = room.calls[0]
        claude.state = .ready
        let model = IslandModel()
        model.metrics = variant.hasSuffix("-flat") ? .init(notch: false, width: 0, height: 0, top: 30)
            : .init(notch: true, width: 186, height: 32, top: 0)
        switch variant.replacingOccurrences(of: "-flat", with: "") {
        case "live":
            claude.state = .speaking
            claude.lines = [.init(role: .agent, text: "Done. The changelog has the new voice section and the build number is bumped.")]
        case "listening":
            claude.state = .listening
        case "asking":
            let guest = room.call(for: Guest(id: "demo", name: "omp", client: "omp-coding-agent",
                                             folder: URL(fileURLWithPath: "/Users/me/dev/landing-page")))
            guest.questionText = "Which colour should the subtitle be?"
            guest.questionChoices = ["Red", "Green", "Blue"]
            guest.questionSince = .now - 20
            guest.questionDeadline = .now + 100
            guest.state = .waiting
            room.focus(guest)
        case "silent":
            room.setSilent(true)
            claude.state = .thinking
            claude.lines = [.init(role: .agent, text: "Two things are left: the changelog needs the voice section, and the build number hasn't been bumped yet.")]
        case "approving":
            claude.state = .waiting
            claude.pendingApproval = ApprovalRequest(id: "demo", tool: "Bash", summary: "Bump the build number in Info.plist and commit it", canAlwaysAllow: true)
        default:
            room.calls[1].state = .thinking
        }
        let view = ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.32, green: 0.36, blue: 0.5), Color(red: 0.16, green: 0.17, blue: 0.24)],
                           startPoint: .top, endPoint: .bottom)
            Rectangle().fill(.black.opacity(0.25)).frame(height: 32)
            if model.metrics.notch { UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10).fill(.black).frame(width: 186, height: 32) }
            IslandView(room: room, model: model)
        }
        .frame(width: Island.canvas.width, height: Island.canvas.height)
        .environment(\.renderTime, 0)
        writePNG(view, scale: 2, to: url)
    }

    /// The welcome window in `loading`, `ready` or `denied`, drawn in a hidden window so native controls render.
    static func writeWelcome(to url: URL, variant: String, appearance: String) {
        let file = FileManager.default.temporaryDirectory.appending(path: "lair-welcome-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        // A folder holding `npx` and `omp` stands in for the login shell's PATH: Claude, Codex and omp are installed.
        let programs = file.appending(path: "bin")
        try? FileManager.default.createDirectory(at: programs, withIntermediateDirectories: true)
        for program in ["npx", "omp"] {
            FileManager.default.createFile(atPath: programs.appending(path: program).path, contents: Data(),
                                           attributes: [.posixPermissions: 0o755])
        }
        var config = LairConfig.initial
        if variant == "ready" {
            var agent = config.newAgent(named: "Claude", voices: VoiceModels.voices)
            AgentChoice.preset(AgentPreset.claude.id).apply(to: &agent)
            config.agents.append(agent)
        }
        let configURL = file.appending(path: "config.json")
        try? config.save(to: configURL)
        let store = ConfigStore(url: configURL)
        let room = Room(config: store.config)
        room.environment = ["PATH": programs.path]
        switch variant {
        case "ready": room.readiness = .ready
        case "denied": room.readiness = .microphoneDenied
        default:
            room.readiness = .loading
            room.voiceProgress = .recognition(0.42)
        }
        let view = NSHostingView(rootView: WelcomeView(store: store, room: room)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, appearance == "light" ? .light : .dark)
            .environment(\.renderTime, 0))
        let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        window.appearance = NSAppearance(named: appearance == "light" ? .aqua : .darkAqua)
        window.setContentSize(view.fittingSize)
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

private extension NSView {
    func firstDescendant<T: NSView>(ofType type: T.Type) -> T? {
        for child in subviews { if let found = child as? T ?? child.firstDescendant(ofType: type) { return found } }
        return nil
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
