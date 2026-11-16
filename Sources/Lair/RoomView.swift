import KeyboardShortcuts
import LairCore
import LairVoice
import SwiftUI

/// The menu-bar panel: everyone in the room down the side, the one you're talking to in the middle,
/// and whoever else needs you right above it.
struct RoomView: View {
    let room: Room
    /// The config file has an error; Lair keeps running with the last good version until it's fixed.
    var configProblem: String?
    var updates: Updates?
    @Environment(\.openWindow) private var openWindow
    @Environment(\.renderTime) private var renderTime
    /// Whether the sidebar has more above and below what shows, so its edges fade only when there's something to scroll to.
    @State private var railMore = (above: false, below: false)
    /// Snapshots can't scroll, so they compare the list's height with its box instead.
    @State private var railContent = CGFloat.zero
    @State private var railBox = CGFloat.zero
    /// With a call the panel is this tall and the transcript scrolls, so a long exchange never grows it off the screen.
    private static let height: CGFloat = 580

    var body: some View {
        let call = room.focused
        let tint = call.map { Color(hex: $0.agent.color) } ?? Color(hex: "#8A8F98")
        VStack(spacing: 0) {
            if let configProblem {
                Banner(text: configProblem, action: "Open file") { NSWorkspace.shared.open(LairConfig.defaultURL) }
                    .padding(.horizontal, 16).padding(.vertical, 10)
            }
            if let call {
                HStack(spacing: 0) {
                    sidebar
                    Divider()
                    conversation(call, tint: tint)
                }
            } else {
                emptyState.padding(16)
                footer.padding([.horizontal, .bottom], 16)
            }
        }
        .frame(width: call == nil ? 340 : 480, height: call == nil ? nil : Self.height)
        .motion(.smooth(duration: 0.3), value: call?.pendingApproval)
        .motion(.smooth(duration: 0.3), value: call?.questionText)
        .motion(.smooth(duration: 0.3), value: room.focusedID)
        .motion(.smooth(duration: 0.3), value: room.calls.map(\.id))
        .background(Backdrop(tint: tint, live: call?.inCall == true, center: call == nil ? 0.5 : 0.7))
    }

    /// Settings, Mission Control and the rest, beside the model switcher.
    private var moreMenu: some View {
        Menu {
            if let updates, let version = updates.reminder.version {
                Button("Install Lair \(version)") { updates.install() }
                Divider()
            }
            Button("Mission Control…\(missionControlKey)") { MissionControl.toggle(room: room) }
            Toggle("Silent mode", isOn: Binding(get: { room.silent }, set: { room.setSilent($0) }))
            Button("Settings…") { openSettings(.agents) }
            Button("Connect agents on this Mac…") { openSettings(.mac) }
            Divider()
            Button("Quit Lair") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 26, height: 26)
                .controlSurface(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.primary)
        .accessibilityLabel("More")
    }

    // MARK: The sidebar

    /// Everyone in the room: the agents you call, then the ones that came to you from this Mac. The list scrolls by
    /// itself, so it never sets the panel's height.
    private var sidebar: some View {
        let agents = room.calls.filter { !$0.stranger }, guests = room.calls.filter(\.stranger)
        let content = VStack(alignment: .leading, spacing: 2) {
            sectionLabel("Agents")
            ForEach(agents) { row($0) }
            if !guests.isEmpty {
                sectionLabel("This Mac")
                    .padding(.top, 8)
                    .help("Sessions on this Mac that aren't one of your agents")
                ForEach(guests) { row($0) }
            }
        }
        // Scroll views don't render offscreen: snapshots get the top of the list, clipped.
        let list = Group {
            if renderTime == nil {
                ScrollView(showsIndicators: false) { content }
                    .onScrollGeometryChange(for: RailEdges.self) {
                        RailEdges(above: $0.contentOffset.y > 1,
                                  below: $0.contentOffset.y + $0.containerSize.height < $0.contentSize.height - 1)
                    } action: { _, edges in railMore = (edges.above, edges.below) }
            } else {
                Color.clear.overlay(alignment: .top) {
                    content.fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { railContent = $0 }
                }
                .clipped()
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { railBox = $0 }
            }
        }
        .mask(railFade)
        .onChange(of: railContent > railBox + 1) { railMore.below = railContent > railBox + 1 }
        .frame(maxHeight: .infinity)
        return VStack(alignment: .leading, spacing: 4) {
            list
            Button { openSettings(agents.isEmpty ? .mac : .agents) } label: {
                Label("Add agent", systemImage: "plus")
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Add an agent, or connect the ones you run on this Mac")
            .accessibilityLabel("Add an agent")
        }
        .padding(8)
        .frame(width: 140)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6).padding(.vertical, 4)
    }

    /// Opaque in the middle, fading out over the last 20 pt of an edge that has more behind it.
    private var railFade: some View {
        GeometryReader { geometry in
            let fade = min(20 / max(geometry.size.height, 1), 0.5)
            LinearGradient(stops: [.init(color: .black.opacity(railMore.above ? 0 : 1), location: 0),
                                   .init(color: .black, location: fade), .init(color: .black, location: 1 - fade),
                                   .init(color: .black.opacity(railMore.below ? 0 : 1), location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    private func row(_ call: Call) -> some View {
        SidebarRow(call: call, focused: call.id == room.focusedID) { room.focus(call) }
    }

    // MARK: The one you're talking to

    private func conversation(_ call: Call, tint: Color) -> some View {
        VStack(spacing: 0) {
            header(call)
            Divider()
            if call.lines.isEmpty { stage(call, tint: tint) } else { problem.padding(.horizontal, 14).padding(.top, 8) }
            Transcript(lines: call.lines, tips: tips(for: call), perform: perform)
                .id(call.id)
                .padding(.horizontal, 14)
            if let request = call.pendingApproval {
                ApprovalCard(agent: call.agent.name, request: request, tint: tint,
                             answer: { room.answer(call, decision: $0) })
                    .padding(.horizontal, 14).padding(.top, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let question = call.questionText {
                QuestionCard(agent: call.agent.name, question: question, choices: call.questionChoices, since: call.questionSince,
                             deadline: call.questionDeadline, tint: tint,
                             answer: { room.answerQuestion(of: call, with: $0) }, skip: { room.skipQuestion(of: call) })
                    .padding(.horizontal, 14).padding(.top, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            controls(call).padding(.top, 10).padding(.bottom, statusMentionsTalkKey(call) ? 16 : 6)
            if !statusMentionsTalkKey(call) { footer.padding(.bottom, 12) }
        }
        .frame(maxWidth: .infinity)
    }

    /// Name and where the call is on the left; model, silent mode and the menu on the right. With no words yet the stage
    /// has the name, so the header keeps to the controls.
    private func header(_ call: Call) -> some View {
        HStack(spacing: 8) {
            if call.lines.isEmpty {
                Spacer(minLength: 0)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(call.agent.name)
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .lineLimit(1)
                        .layoutPriority(1)
                    if call.guest { GuestBadge(folder: call.folder) }
                    if readinessProblem == nil { caption(call, style: .caption) }
                }
                Spacer(minLength: 0)
            }
            trailing(call)
            if room.silent {
                Image(systemName: "speaker.slash.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .help("Silent mode: Lair writes instead of speaking")
                    .accessibilityLabel("Silent mode")
            }
            moreMenu
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(minHeight: 52)
    }

    /// The model menu, or what a guest or Hermes can say about itself.
    @ViewBuilder private func trailing(_ call: Call) -> some View {
        if call.guest {
            if room.canAdopt(call) { adoptButton(call) }
        } else if call.inCall && call.agent.kind != .hermes {
            ModelSwitcher(call: call, room: room)
        } else if let details = call.details {
            Text(details)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func adoptButton(_ call: Call) -> some View {
        Button { room.adopt(call) } label: {
            Label("Make it an agent", systemImage: "person.crop.circle.badge.plus")
        }
        .buttonStyle(PillButtonStyle())
        .help("Save this tool and folder as an agent: give it a voice, a soul and a purpose in Settings")
    }

    /// The agent's orb; a tap starts a call, while hanging up stays on the red button so a stray click can't end one.
    private func orb(_ call: Call, tint: Color) -> some View {
        Orb(color: tint, state: call.state, meter: room.meter(for: call))
            .contentShape(Circle())
            .onTapGesture { if !call.inCall, !call.guest { room.summon(call) } }
            .accessibilityElement()
            .accessibilityLabel("\(call.agent.name), \(call.state.label)")
            .accessibilityAddTraits(call.inCall || call.guest ? [] : .isButton)
            .accessibilityAction { if !call.inCall, !call.guest { room.summon(call) } }
    }

    /// The big orb and name, for a call with no words yet.
    private func stage(_ call: Call, tint: Color) -> some View {
        VStack(spacing: 12) {
            orb(call, tint: tint)
                .frame(width: 96, height: 96)
                .frame(height: 124)
            VStack(spacing: 4) {
                Text(call.agent.name)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .lineLimit(1)
                if call.guest { GuestBadge(folder: call.folder) }
                if readinessProblem == nil { caption(call, style: .subheadline).multilineTextAlignment(.center) }
                problem
            }
        }
    }

    /// What's in the way of talking, and how to fix it; nothing while the microphone and voices are fine.
    private var readinessProblem: String? {
        switch room.readiness {
        case .microphoneDenied: "Lair needs your microphone to hear you."
        case .failed(let message): message
        case .loading, .ready: nil
        }
    }

    @ViewBuilder private var problem: some View {
        if let text = readinessProblem {
            Problem(text: text) {
                if room.readiness == .microphoneDenied {
                    Button("Open Privacy Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                    }
                }
                Button("Try again") { Task { await room.prepare() } }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Where the call is and how to talk to it.
    private func caption(_ call: Call, style: Font.TextStyle) -> some View {
        let text = room.hint ?? caption(for: call)
        return Text(text)
            .font(.system(style, design: .rounded))
            .foregroundStyle(room.hint == nil ? .secondary : .primary)
            .lineLimit(2)
            .contentTransition(.opacity)
            .motion(.easeInOut(duration: 0.2), value: text)
    }

    /// The talk button in the middle; on its left the call button, or Dismiss for a guest; on its right Continue at
    /// keyboard for agents whose CLI can pick the call up.
    private func controls(_ call: Call) -> some View {
        HStack(spacing: 24) {
            if call.guest {
                // A guest isn't called or hung up: it comes and goes on its own, and can be sent away.
                RoundButton(symbol: "xmark", tint: nil, size: 38) { room.toggle(call) }
                    .help("Dismiss \(call.agent.name); it comes back when it next talks to you")
                    .accessibilityLabel("Dismiss \(call.agent.name)")
                    .accessibilityValue(call.state.label)
            } else if call.atKeyboard != nil {
                RoundButton(symbol: "arrow.uturn.backward", tint: LairColors.call, size: 38) { room.toggle(call) }
                    .disabled(room.readiness != .ready)
                    .help("Bring \(call.agent.name) back from the keyboard, once you've quit its CLI")
                    .accessibilityLabel("Bring \(call.agent.name) back from the keyboard")
            } else {
                RoundButton(symbol: call.inCall ? "phone.down.fill" : "phone.fill",
                            tint: call.inCall ? LairColors.hangUp : LairColors.call,
                            size: 38) { room.toggle(call) }
                    .disabled(room.readiness != .ready)
                    .help(call.inCall ? "Hang up" : "Call \(call.agent.name)")
                    .accessibilityLabel(call.inCall ? "Hang up \(call.agent.name)" : "Call \(call.agent.name)")
                    .accessibilityValue(call.state.label)
            }
            let deaf = call.guest && call.questionText == nil
            HoldToTalk(active: call.state == .listening, tint: Color(hex: call.agent.color),
                       answering: room.answering?.callID == call.id ? room.answering : nil, size: 56,
                       onPress: room.pressTalk, onRelease: room.releaseTalk)
                .disabled(room.readiness != .ready || deaf)
                .opacity(deaf ? 0.35 : 1)
                .help(deaf ? "\(call.agent.name) listens when it asks you something" : "Hold to talk")
            if room.canHandOff(call) {
                RoundButton(symbol: "keyboard", tint: nil, size: 38) { room.handOff(call) }
                    .disabled(call.state != .ready)
                    .help(call.state == .ready
                          ? "Continue at keyboard: go on with \(call.agent.name) in its CLI; quit it to come back here"
                          : "Continue at keyboard, once \(call.agent.name) is in a call and between turns")
                    .accessibilityLabel("Continue \(call.agent.name) at the keyboard")
            }
        }
    }

    private var missionControlKey: String {
        KeyboardShortcuts.getShortcut(for: .missionControl).map { " (\($0))" } ?? ""
    }

    /// What you can say, shown while a call has no words yet.
    private func tips(for call: Call) -> [String] {
        guard !call.guest else { return [] }
        let other = room.calls.first { $0.id != call.id && !$0.guest }?.agent.name
        return ["Answer right after it speaks: Lair listens for a few seconds.",
                other.map { "Say “\($0), …” to talk to \($0) instead." },
                other.map { "Say “ask \($0) what it thinks” to pass this on." },
                call.agent.kind == .hermes ? nil : "Say “switch to Opus”, “think harder” or “go fast”.",
                "Talk over it to cut it off."].compactMap { $0 }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.wave.2")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.primary)
            Text("No one here yet")
                .font(.system(.title3, design: .rounded, weight: .semibold))
            Text("Add an agent to call by voice, or let the agents you run in a terminal talk to you.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(spacing: 8) {
                Button { openSettings(.agents) } label: {
                    Text("Add an agent…")
                        .font(.system(.callout, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color.inverse)
                        .frame(maxWidth: 260).padding(.vertical, 8)
                        .background(.primary, in: Capsule())
                }
                Button { openSettings(.mac) } label: {
                    Label("Connect agents on this Mac…", systemImage: "laptopcomputer")
                        .font(.system(.callout, design: .rounded, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: 260).padding(.vertical, 8)
                        .background(Color.primary.opacity(0.12), in: Capsule())
                        .outlined(Capsule(), opacity: 0)
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.vertical, 36)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var footer: some View {
        if let shortcut = TalkKey.shared.label {
            HStack(spacing: 6) {
                Text("Hold")
                Text(shortcut)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                Text("anywhere to talk")
            }
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(.secondary)
        } else {
            Button { openSettings(.general) } label: {
                Text("Set a talk shortcut in Settings…").contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .font(.system(.caption, design: .rounded, weight: .medium))
            .foregroundStyle(.primary)
        }
    }

    private func openSettings(_ tab: SettingsView.Tab) {
        SettingsRoute.shared.tab = tab
        openWindow(id: SettingsView.id)
        SettingsView.bringForward()
    }

    private func perform(_ action: Call.Line.Action) {
        switch action {
        case .openSettings: openSettings(.agents)
        case .showLog(let agentID): NSWorkspace.shared.open(AgentLog.url(for: agentID))
        }
    }

    private func caption(for call: Call) -> String {
        if room.readiness == .loading { return "Getting the voices ready… the first launch downloads them once." }
        let key = TalkKey.shared.label ?? "the talk key"
        if call.guest {
            switch call.state {
            case .offline: return "Left · it's back when it talks to you again"
            case .listening where room.answering?.callID == call.id: return "Listening for your answer · just talk"
            case .listening: return "Listening… let go when you're done"
            case .speaking: return "Speaking"
            case .waiting where call.questionText != nil: return "Asks you · say it, type it, or hold \(key)"
            default: return "Working on its own · talks to you when it needs you"
            }
        }
        switch call.state {
        case .offline where call.atKeyboard != nil: return "At your keyboard · quit its CLI to bring it back"
        case .offline: return "Hold \(key) to talk, or tap the orb"
        case .ready: return "Hold \(key) to talk"
        case .listening where room.answering?.callID == call.id: return "Listening for your reply · just talk"
        case .listening: return "Listening… let go when you're done"
        case .thinking: return "Thinking… hold \(key) to cut in"
        case .speaking: return "Speaking · hold \(key) to cut in"
        case .waiting:
            return call.pendingApproval?.canAlwaysAllow == true ? "Your OK? Say yes, always or no" : "Your OK? Say yes or no"
        }
    }

    /// The state line already tells how to talk, so the footer's hint would say it twice.
    private func statusMentionsTalkKey(_ call: Call) -> Bool {
        guard let key = TalkKey.shared.label else { return false }
        return (room.hint ?? caption(for: call)).contains(key)
    }
}

/// Round control with a symbol.
private struct RoundButton: View {
    let symbol: String
    /// A call's color (green, red), or nothing for a neutral control.
    let tint: Color?
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(tint == nil ? .primary : Color.white)
                .frame(width: size, height: size)
                .controlSurface(Circle(), tint: tint)
        }
        .buttonStyle(.plain)
    }
}

/// Which edges of the rail have more behind them.
private struct RailEdges: Equatable {
    let above: Bool
    let below: Bool
}
