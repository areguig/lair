import LairCore
import LairVoice
import SwiftUI

/// The menu-bar panel: the focused agent's orb, what was said, and the call controls.
struct RoomView: View {
    let room: Room
    /// The config file has an error; Lair keeps running with the last good version until it's fixed.
    var configProblem: String?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let call = room.focused
        let tint = call.map { Color(hex: $0.agent.color) } ?? Color(hex: "#8A8F98")
        VStack(spacing: 0) {
            header
            if let configProblem {
                Banner(text: configProblem, action: "Open file") { NSWorkspace.shared.open(LairConfig.defaultURL) }
                    .padding(.top, 10)
            }
            if let call {
                stage(call, tint: tint)
                if room.calls.count > 1 { roster.padding(.top, 14) }
                Transcript(lines: call.lines, live: call.inCall, tips: tips(for: call), perform: perform)
                    .padding(.top, 16)
                if let request = call.pendingApproval {
                    ApprovalCard(agent: call.agent.name, request: request, tint: tint,
                                 answer: { room.answer(call, decision: $0) })
                        .padding(.top, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                controls(call).padding(.top, 14)
            } else {
                emptyState
            }
            footer.padding(.top, 14)
        }
        .padding(18)
        .frame(width: 340)
        .animation(.smooth(duration: 0.3), value: call?.pendingApproval)
        .animation(.smooth(duration: 0.3), value: room.focusedID)
        .background(Backdrop(tint: tint, live: call?.inCall == true))
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack {
            Text("Lair")
                .font(.system(.headline, design: .rounded, weight: .semibold))
            Spacer()
            Menu {
                Button("Mission Control…") { MissionControl.toggle(room: room) }
                Button("Settings…", action: openSettings)
                Divider()
                Button("Quit Lair") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .background(.white.opacity(0.08), in: Circle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More")
        }
        .foregroundStyle(.white.opacity(0.9))
    }

    private func stage(_ call: Call, tint: Color) -> some View {
        VStack(spacing: 14) {
            Orb(color: tint, state: call.state, meter: room.meter(for: call))
                .frame(width: 112, height: 112)
                .frame(height: 150)
                .contentShape(Circle())
                // Starts a call; hanging up stays on the red button, so a stray click can't end one.
                .onTapGesture { if !call.inCall { room.summon(call) } }
                .accessibilityElement()
                .accessibilityLabel("\(call.agent.name), \(spoken(call.state))")
                .accessibilityAddTraits(call.inCall ? [] : .isButton)
                .accessibilityAction { if !call.inCall { room.summon(call) } }
            VStack(spacing: 4) {
                Text(call.agent.name)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .lineLimit(1)
                if call.inCall && call.agent.kind != .hermes {
                    ModelSwitcher(call: call, room: room)
                } else if let details = call.details {
                    Text(details)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .transition(.opacity)
                }
                status(for: call)
            }
        }
        .padding(.top, 4)
    }

    /// The caption under the name, or what's in the way and how to fix it.
    @ViewBuilder private func status(for call: Call) -> some View {
        switch room.readiness {
        case .microphoneDenied:
            Problem(text: "Lair needs your microphone to hear you.") {
                Button("Open Privacy Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                }
                Button("Try again") { Task { await room.prepare() } }
            }
        case .failed(let message):
            Problem(text: message) {
                Button("Try again") { Task { await room.prepare() } }
            }
        case .loading, .ready:
            let text = room.hint ?? caption(for: call)
            Text(text)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.white.opacity(room.hint == nil ? 0.62 : 0.9))
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: text)
        }
    }

    private var roster: some View {
        // Centered while the chips fit, scrolling sideways once there are more agents than room.
        ViewThatFits(in: .horizontal) {
            chips
            ScrollView(.horizontal, showsIndicators: false) { chips }
        }
    }

    private var chips: some View {
        HStack(spacing: 8) {
            ForEach(room.calls) { call in
                Button { room.focus(call) } label: {
                    HStack(spacing: 6) {
                        StatusDot(color: Color(hex: call.agent.color), state: call.state)
                        Text(call.agent.name)
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .lineLimit(1)
                            .frame(maxWidth: 96)
                            .fixedSize()
                        if call.state == .waiting {
                            Image(systemName: "hand.raised.fill").font(.system(size: 9)).foregroundStyle(.orange)
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.white.opacity(call.id == room.focusedID ? 0.14 : 0.05), in: Capsule())
                    .overlay(alignment: .topTrailing) {
                        if call.unread && call.id != room.focusedID {
                            Circle().fill(.white).frame(width: 7, height: 7).offset(x: 1, y: -1)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help(call.unread ? "\(call.agent.name) has news" : call.agent.name)
                .accessibilityLabel([call.agent.name, spoken(call.state), call.unread ? "has news" : nil]
                    .compactMap { $0 }.joined(separator: ", "))
            }
        }
        .padding(.vertical, 2)
    }

    /// The talk button in the middle, the call button on its left and Mission Control on its right.
    private func controls(_ call: Call) -> some View {
        HStack(spacing: 28) {
            RoundButton(symbol: call.inCall ? "phone.down.fill" : "phone.fill",
                        fill: call.inCall ? Color(red: 0.92, green: 0.3, blue: 0.3) : Color(red: 0.25, green: 0.75, blue: 0.45),
                        size: 44) { room.toggle(call) }
                .disabled(room.readiness != .ready)
                .help(call.inCall ? "Hang up" : "Call \(call.agent.name)")
                .accessibilityLabel(call.inCall ? "Hang up" : "Call \(call.agent.name)")
            HoldToTalk(active: call.state == .listening, tint: Color(hex: call.agent.color),
                       answering: room.answering?.callID == call.id ? room.answering : nil,
                       onPress: room.pressTalk, onRelease: room.releaseTalk)
                .disabled(room.readiness != .ready)
            RoundButton(symbol: "rectangle.split.3x1", fill: .white.opacity(0.1), size: 44) {
                MissionControl.toggle(room: room)
            }
            .help("Mission Control: every agent's whole stream")
            .accessibilityLabel("Mission Control")
        }
    }

    /// What you can say, shown while a call has no words yet.
    private func tips(for call: Call) -> [String] {
        let other = room.calls.first { $0.id != call.id }?.agent.name
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
                .foregroundStyle(.white.opacity(0.7))
            Text("No agents yet")
                .font(.system(.title3, design: .rounded, weight: .semibold))
            Text("Add Claude Code, omp or a Hermes agent, then hold the talk key to call it.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
                .multilineTextAlignment(.center)
            Button(action: openSettings) {
                Text("Add an agent…")
                    .font(.system(.callout, design: .rounded, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    .background(.white, in: Capsule())
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
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                Text("anywhere to talk")
            }
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(.white.opacity(0.6))
        } else {
            Button("Set a talk shortcut in Settings…", action: openSettings)
                .buttonStyle(.plain)
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
        }
    }

    private func openSettings() {
        openWindow(id: SettingsView.id)
        SettingsView.bringForward()
    }

    private func perform(_ action: Call.Line.Action) {
        switch action {
        case .openSettings: openSettings()
        case .showLog(let agentID): NSWorkspace.shared.open(AgentLog.url(for: agentID))
        }
    }

    private func caption(for call: Call) -> String {
        if room.readiness == .loading { return "Getting the voices ready… the first launch downloads them once." }
        let key = TalkKey.shared.label ?? "the talk key"
        switch call.state {
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

    private func spoken(_ state: Call.State) -> String {
        switch state {
        case .offline: "not in a call"
        case .ready: "in a call"
        case .listening: "listening"
        case .thinking: "thinking"
        case .speaking: "speaking"
        case .waiting: "waiting for your OK"
        }
    }
}

/// The model line under the name, during a call: click it to switch model or thinking for this call.
private struct ModelSwitcher: View {
    let call: Call
    let room: Room

    var body: some View {
        let models = call.models
        let levels = call.session?.thinkingLevels ?? []
        Menu {
            if !models.isEmpty {
                Section("Model") {
                    ForEach(models, id: \.self) { model in
                        Button(model) { run(.model(model)) }
                    }
                }
            }
            if !levels.isEmpty {
                Section(call.agent.kind == .claudeCode ? "Effort, from the next call" : "Thinking") {
                    ForEach(levels, id: \.self) { level in
                        Toggle(level, isOn: Binding(get: { (call.thinkingNextCall ?? call.thinking) == level },
                                                    set: { _ in run(.thinking(level)) }))
                    }
                }
            }
            Divider()
            Button("Go fast", systemImage: "hare") { run(.fast) }
            Button("Go deep", systemImage: "tortoise") { run(.deep) }
        } label: {
            HStack(spacing: 4) {
                Text(call.details ?? "Choose model")
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.white.opacity(0.62))
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(.white.opacity(0.06), in: Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Switch model or thinking for this call — or just say “switch to Opus”, “think harder”")
        .accessibilityLabel("Model: \(call.details ?? "default"). Switch model or thinking")
    }

    private func run(_ command: VoiceCommand) {
        Task { await room.run(command, in: call) }
    }
}

/// A problem with its way out, under the agent's name.
private struct Problem<Actions: View>: View {
    let text: String
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(spacing: 8) {
            Label(text, systemImage: "exclamationmark.triangle.fill")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
            HStack(spacing: 8) { actions }
                .buttonStyle(PillButtonStyle())
        }
    }
}

/// A slim warning across the panel, with one action.
private struct Banner: View {
    let text: String
    let action: String
    let perform: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(text)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
            Spacer(minLength: 4)
            Button(action, action: perform).buttonStyle(PillButtonStyle())
        }
        .padding(10)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Small rounded buttons used for actions inside the panel.
private struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(.white.opacity(configuration.isPressed ? 0.24 : 0.14), in: Capsule())
    }
}

/// What was said in this call, newest at the bottom, fading out at the top.
private struct Transcript: View {
    let lines: [Call.Line]
    /// In a call, the space stays reserved so the panel doesn't jump at the first words.
    let live: Bool
    /// Shown in turn while there are no words yet.
    let tips: [String]
    let perform: (Call.Line.Action) -> Void
    @Environment(\.renderTime) private var renderTime

    var body: some View {
        Group {
            if lines.isEmpty {
                TimelineView(.periodic(from: .now, by: 6)) { timeline in
                    let tick = Int(renderTime ?? timeline.date.timeIntervalSinceReferenceDate) / 6
                    Text(tips.isEmpty ? "" : tips[tick % tips.count])
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                        .multilineTextAlignment(.center)
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.4), value: tick)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if renderTime == nil {
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(lines) { line in
                            row(line)
                        }
                    }
                    .padding(.vertical, 12)
                }
                // Stays pinned to the newest words as the reply streams in.
                .defaultScrollAnchor(.bottom)
            } else {
                // Scroll views don't render offscreen: the newest lines, bottom-aligned, instead.
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(lines.suffix(4)) { line in
                        row(line).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .clipped()
            }
        }
        .frame(height: lines.isEmpty ? (live ? 44 : 0) : 150)
        .opacity(lines.isEmpty && !live ? 0 : 1)
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.18),
                                     .init(color: .black, location: 1)], startPoint: .top, endPoint: .bottom))
        .animation(.smooth, value: lines.isEmpty)
        .animation(.smooth, value: live)
    }

    @ViewBuilder private func row(_ line: Call.Line) -> some View {
        switch line.role {
        case .you:
            Text(line.text)
                .textSelection(.enabled)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 40)
        case .agent:
            VStack(alignment: .leading, spacing: 6) {
                if !line.text.isEmpty || line.shown.isEmpty {
                    Text(line.text.isEmpty ? "…" : line.text)
                        .textSelection(.enabled)
                        .foregroundStyle(.white.opacity(0.9))
                }
                ForEach(Array(line.shown.enumerated()), id: \.offset) { _, item in
                    ShownChip(item: item)
                }
            }
            .padding(.trailing, 24)
        case .info:
            Label(line.text, systemImage: "info.circle")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(2)
        case .problem:
            VStack(alignment: .leading, spacing: 6) {
                Label(line.text, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
                if let action = line.action {
                    Button(action.title) { perform(action) }.buttonStyle(PillButtonStyle())
                }
            }
        }
    }
}

/// Something the agent showed instead of saying: a link opens, a path shows in Finder, anything else copies.
private struct ShownChip: View {
    let item: String
    @State private var copied = false

    var body: some View {
        Button(action: use) {
            Label {
                Text(copied ? "Copied" : item)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(systemName: copied ? "checkmark" : symbol)
            }
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(item)
        .accessibilityLabel("\(kind): \(item)")
    }

    private var url: URL? {
        guard let url = URL(string: item), ["http", "https"].contains(url.scheme ?? "") else { return nil }
        return url
    }

    private var path: String? {
        item.hasPrefix("/") || item.hasPrefix("~") ? NSString(string: item).expandingTildeInPath : nil
    }

    private var symbol: String { url != nil ? "link" : path != nil ? "folder" : "doc.on.doc" }
    private var kind: String { url != nil ? "Open link" : path != nil ? "Show in Finder" : "Copy" }

    private func use() {
        if let url {
            NSWorkspace.shared.open(url)
        } else if let path, FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        } else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item, forType: .string)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                copied = false
            }
        }
    }
}

private extension Call.Line.Action {
    var title: String {
        switch self {
        case .openSettings: "Open Settings"
        case .showLog: "Show log"
        }
    }
}

/// What the agent wants to do, with the same Allow and Deny as the notification and your voice.
struct ApprovalCard: View {
    let agent: String
    let request: ApprovalRequest
    let tint: Color
    /// Return and Escape answer it; off where several cards or a text field share the window.
    var shortcuts = true
    let answer: (ApprovalDecision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill").foregroundStyle(tint)
                Text("\(agent) needs your OK").font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(request.tool)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
            }
            // A long command stays readable without pushing the panel off screen; the whole text is in the tooltip.
            Text(request.summary)
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(5)
                .fixedSize(horizontal: false, vertical: true)
                .help(request.summary)
                .textSelection(.enabled)
            HStack(spacing: 8) {
                Button { answer(.deny) } label: {
                    Text("Deny").frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(.white.opacity(0.1), in: Capsule())
                }
                .keyboardShortcut(shortcuts ? .cancelAction : nil)
                if request.canAlwaysAllow {
                    Button { answer(.allowAlways) } label: {
                        Text("Always allow").fontWeight(.semibold).foregroundStyle(tint).lineLimit(1)
                            .frame(maxWidth: .infinity).padding(.vertical, 7)
                            .background(tint.opacity(0.22), in: Capsule())
                    }
                }
                Button { answer(.allowOnce) } label: {
                    Text("Allow").fontWeight(.semibold).foregroundStyle(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(.white, in: Capsule())
                }
                .keyboardShortcut(shortcuts ? .defaultAction : nil)
            }
            .buttonStyle(.plain)
            .font(.system(.callout, design: .rounded))
        }
        .padding(14)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(tint.opacity(0.5), lineWidth: 1))
    }
}

/// The agent's color, dim when offline and breathing while it works.
private struct StatusDot: View {
    let color: Color
    let state: Call.State
    @Environment(\.renderTime) private var renderTime

    var body: some View {
        let working = state == .thinking || state == .speaking
        TimelineView(.animation(paused: !working)) { timeline in
            let time = renderTime ?? timeline.date.timeIntervalSinceReferenceDate
            let pulse = working ? (sin(time * 5) + 1) / 2 : 0
            Circle().fill(color)
                .frame(width: 8, height: 8)
                .opacity(state == .offline ? 0.4 : 1)
                .shadow(color: color.opacity(working ? 0.9 : 0), radius: 2 + pulse * 3)
                .scaleEffect(1 + pulse * 0.25)
        }
        .frame(width: 10, height: 10)
    }
}

/// Round control with a symbol.
private struct RoundButton: View {
    let symbol: String
    let fill: Color
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(fill, in: Circle())
        }
        .buttonStyle(.plain)
    }
}

/// Press and hold to talk; the ring lights up while listening.
private struct HoldToTalk: View {
    let active: Bool
    let tint: Color
    var answering: Room.Answering?
    let onPress: () -> Void
    let onRelease: () -> Void
    @State private var pressed = false

    var body: some View {
        Image(systemName: "mic.fill")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(active ? .black : .white)
            .frame(width: 64, height: 64)
            .background(active ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.14)), in: Circle())
            .overlay {
                if let answering {
                    ReplyCountdown(answering: answering, tint: tint, lineWidth: 3).padding(-5)
                } else {
                    Circle().strokeBorder(tint.opacity(active ? 0.9 : 0), lineWidth: 3).padding(-5)
                }
            }
            .scaleEffect(pressed ? 0.94 : 1)
            .animation(.spring(duration: 0.25), value: pressed)
            .animation(.easeOut(duration: 0.2), value: active)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if !pressed { pressed = true; onPress() } }
                .onEnded { _ in pressed = false; onRelease() })
            .help("Hold to talk")
            .accessibilityElement()
            .accessibilityLabel(active ? "Listening; release to send" : "Hold to talk")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: active ? "Send" : "Start talking") { active ? onRelease() : onPress() }
    }
}

/// While Lair waits for your reply, a ring that empties as the wait runs out, and stays full once you talk.
struct ReplyCountdown: View {
    let answering: Room.Answering
    let tint: Color
    let lineWidth: CGFloat
    @Environment(\.renderTime) private var renderTime

    var body: some View {
        TimelineView(.animation(paused: answering.hearing)) { timeline in
            let patience = Double(FollowUp.Turn.patience.components.seconds)
            let elapsed = renderTime.map { $0.truncatingRemainder(dividingBy: patience) }
                ?? timeline.date.timeIntervalSince(answering.since)
            let left = answering.hearing ? 1 : max(0, 1 - elapsed / patience)
            Circle()
                .trim(from: 0, to: left)
                .stroke(tint.opacity(0.9), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(lineWidth / 2)
        }
        .accessibilityHidden(true)
    }
}

/// Dark room with a soft glow of the agent's color, brighter during a call.
private struct Backdrop: View {
    let tint: Color
    let live: Bool

    var body: some View {
        ZStack {
            Color(red: 0.055, green: 0.06, blue: 0.075)
            RadialGradient(colors: [tint.opacity(live ? 0.38 : 0.18), .clear], center: UnitPoint(x: 0.5, y: 0.22),
                           startRadius: 0, endRadius: 260)
                .animation(.easeInOut(duration: 0.6), value: live)
        }
    }
}
