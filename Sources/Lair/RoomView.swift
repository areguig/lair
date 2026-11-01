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
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                HStack(alignment: .top, spacing: 14) {
                    rail
                    main(call, tint: tint)
                }
                .padding(.top, 14)
            } else {
                emptyState
            }
            if call.map(statusMentionsTalkKey) != true { footer.padding(.top, 14) }
        }
        .padding(18)
        .frame(width: call == nil ? 340 : 424)
        .animation(.smooth(duration: 0.3), value: call?.pendingApproval)
        .animation(.smooth(duration: 0.3), value: call?.questionText)
        .animation(.smooth(duration: 0.3), value: room.focusedID)
        .animation(.smooth(duration: 0.3), value: room.calls.map(\.id))
        .background(Backdrop(tint: tint, live: call?.inCall == true, center: call == nil ? 0.5 : 0.6))
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Lair")
                .font(.system(.headline, design: .rounded, weight: .semibold))
            if let presence {
                Text(presence)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .contentTransition(.numericText())
            }
            Spacer()
            Menu {
                Button("Mission Control…") { MissionControl.toggle(room: room) }
                Button("Settings…") { openSettings(.agents) }
                Button("Connect agents on this Mac…") { openSettings(.mac) }
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

    /// "2 on a call · 1 on this Mac", or nothing while the room is quiet.
    private var presence: String? {
        let live = room.calls.filter { $0.visitor == nil && $0.inCall }.count
        let guests = room.calls.filter { $0.visitor != nil }.count
        let parts = [live > 0 ? "\(live) on a call" : nil, guests > 0 ? "\(guests) on this Mac" : nil].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: The rail

    /// Everyone in the room: the agents you call, then the ones that came to you from this Mac.
    private var rail: some View {
        let agents = room.calls.filter { !$0.stranger }, guests = room.calls.filter(\.stranger)
        return VStack(spacing: 6) {
            ForEach(agents) { avatar($0) }
            if !guests.isEmpty {
                VStack(spacing: 4) {
                    Capsule().fill(.white.opacity(0.12)).frame(width: 28, height: 1)
                    Text("This Mac")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .textCase(.uppercase)
                        .kerning(0.6)
                        .foregroundStyle(.white.opacity(0.38))
                }
                .padding(.vertical, 4)
                .help("Sessions on this Mac that aren't one of your agents")
                ForEach(guests) { avatar($0) }
            }
            Button { openSettings(agents.isEmpty ? .mac : .agents) } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 34, height: 34)
                    .overlay(Circle().strokeBorder(.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
            }
            .buttonStyle(.plain)
            .help("Add an agent, or connect the ones you run on this Mac")
            .accessibilityLabel("Add an agent")
            .padding(.top, 4)
        }
        .padding(.vertical, 10)
        .frame(width: 68)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.06), lineWidth: 1))
    }

    private func avatar(_ call: Call) -> some View {
        RailAvatar(call: call, focused: call.id == room.focusedID) { room.focus(call) }
    }

    // MARK: The one you're talking to

    private func main(_ call: Call, tint: Color) -> some View {
        VStack(spacing: 0) {
            let waiting = room.calls.filter { $0.id != call.id && $0.awaitsYou }
            if let other = waiting.first {
                ElsewhereBar(call: other, more: waiting.count - 1) { room.focus(other) }
                    .padding(.bottom, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            stage(call, tint: tint)
            Transcript(lines: call.lines, live: call.inCall, tips: tips(for: call), perform: perform)
                .padding(.top, 12)
            if let request = call.pendingApproval {
                ApprovalCard(agent: call.agent.name, request: request, tint: tint,
                             answer: { room.answer(call, decision: $0) })
                    .padding(.top, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let question = call.questionText {
                QuestionCard(agent: call.agent.name, question: question, choices: call.questionChoices, since: call.questionSince,
                             deadline: call.questionDeadline, tint: tint,
                             answer: { room.answerQuestion(of: call, with: $0) }, skip: { room.skipQuestion(of: call) })
                    .padding(.top, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            controls(call).padding(.top, 14)
        }
        .frame(maxWidth: .infinity)
        .animation(.smooth(duration: 0.3), value: room.calls.contains { $0.id != call.id && $0.awaitsYou })
    }

    private func stage(_ call: Call, tint: Color) -> some View {
        // Once there are words, the orb and name shrink to leave the room to the transcript.
        let compact = !call.lines.isEmpty
        return VStack(spacing: compact ? 6 : 12) {
            Orb(color: tint, state: call.state, meter: room.meter(for: call))
                .frame(width: compact ? 56 : 96, height: compact ? 56 : 96)
                .frame(height: compact ? 64 : 124)
                .contentShape(Circle())
                // Starts a call; hanging up stays on the red button, so a stray click can't end one.
                .onTapGesture { if !call.inCall, !call.guest { room.summon(call) } }
                .accessibilityElement()
                .accessibilityLabel("\(call.agent.name), \(spoken(call.state))")
                .accessibilityAddTraits(call.inCall || call.guest ? [] : .isButton)
                .accessibilityAction { if !call.inCall, !call.guest { room.summon(call) } }
            VStack(spacing: 4) {
                Text(call.agent.name)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .lineLimit(1)
                if call.guest {
                    GuestBadge(folder: call.folder)
                    if room.canAdopt(call) {
                        Button { room.adopt(call) } label: {
                            Label("Make it an agent", systemImage: "person.crop.circle.badge.plus")
                                .font(.system(.caption, design: .rounded, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(.white.opacity(0.1), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                        .help("Save this tool and folder as an agent: give it a voice, a soul and a purpose in Settings")
                    }
                } else if call.inCall && call.agent.kind != .hermes {
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
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: compact)
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

    /// The talk button in the middle; on its left the call button, or Dismiss for a guest; Mission Control on its right.
    private func controls(_ call: Call) -> some View {
        HStack(spacing: 26) {
            if call.guest {
                // A guest isn't called or hung up: it comes and goes on its own, and can be sent away.
                RoundButton(symbol: "xmark", fill: .white.opacity(0.1), size: 42) { room.toggle(call) }
                    .help("Dismiss \(call.agent.name); it comes back when it next talks to you")
                    .accessibilityLabel("Dismiss \(call.agent.name)")
            } else {
                RoundButton(symbol: call.inCall ? "phone.down.fill" : "phone.fill",
                            fill: call.inCall ? LairColors.hangUp : LairColors.call,
                            size: 42) { room.toggle(call) }
                    .disabled(room.readiness != .ready)
                    .help(call.inCall ? "Hang up" : "Call \(call.agent.name)")
                    .accessibilityLabel(call.inCall ? "Hang up" : "Call \(call.agent.name)")
            }
            let deaf = call.guest && call.questionText == nil
            HoldToTalk(active: call.state == .listening, tint: Color(hex: call.agent.color),
                       answering: room.answering?.callID == call.id ? room.answering : nil,
                       onPress: room.pressTalk, onRelease: room.releaseTalk)
                .disabled(room.readiness != .ready || deaf)
                .opacity(deaf ? 0.35 : 1)
                .help(deaf ? "\(call.agent.name) listens when it asks you something" : "Hold to talk")
            RoundButton(symbol: "rectangle.split.3x1", fill: .white.opacity(0.1), size: 42) {
                MissionControl.toggle(room: room)
            }
            .help("Mission Control\(missionControlKey): every agent's whole stream")
            .accessibilityLabel("Mission Control\(missionControlKey)")
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
                .foregroundStyle(.white.opacity(0.7))
            Text("No one here yet")
                .font(.system(.title3, design: .rounded, weight: .semibold))
            Text("Add an agent to call by voice, or let the agents you run in a terminal talk to you.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
                .multilineTextAlignment(.center)
            VStack(spacing: 8) {
                Button { openSettings(.agents) } label: {
                    Text("Add an agent…")
                        .font(.system(.callout, design: .rounded, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: 220).padding(.vertical, 8)
                        .background(.white, in: Capsule())
                }
                Button { openSettings(.mac) } label: {
                    Label("Connect agents on this Mac…", systemImage: "laptopcomputer")
                        .font(.system(.callout, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: 220).padding(.vertical, 8)
                        .background(.white.opacity(0.12), in: Capsule())
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
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                Text("anywhere to talk")
            }
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(.white.opacity(0.6))
        } else {
            Button("Set a talk shortcut in Settings…") { openSettings(.general) }
                .buttonStyle(.plain)
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
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

    private func spoken(_ state: Call.State) -> String {
        state.label.lowercased()
    }
}

/// One agent in the rail: its orb, alive with its state; a ring while it speaks; a badge when it needs you.
private struct RailAvatar: View {
    let call: Call
    let focused: Bool
    let select: () -> Void

    var body: some View {
        let tint = Color(hex: call.agent.color)
        Button(action: select) {
            VStack(spacing: 5) {
                ZStack {
                    Circle().fill(.white.opacity(focused ? 0.09 : 0))
                    Orb(color: tint, state: call.state).frame(width: 32, height: 32)
                    if call.state == .speaking { SpeakingRing(tint: tint) }
                    Circle().strokeBorder(tint.opacity(focused ? 0.85 : 0), lineWidth: 1.5)
                }
                .frame(width: 46, height: 46)
                .overlay(alignment: .topTrailing) { badge }
                .overlay(alignment: .bottomTrailing) {
                    if call.guest {
                        Image(systemName: "laptopcomputer")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(width: 15, height: 15)
                            .background(Color(red: 0.12, green: 0.13, blue: 0.15), in: Circle())
                            .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
                    }
                }
                Text(call.agent.name)
                    .font(.system(size: 10, weight: focused ? .semibold : .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(focused ? 0.95 : call.inCall ? 0.7 : 0.45))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .truncationMode(.tail)
                    .frame(width: 60)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    @ViewBuilder private var badge: some View {
        if call.questionText != nil || call.pendingApproval != nil {
            Image(systemName: call.questionText != nil ? "questionmark" : "hand.raised.fill")
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(.black)
                .frame(width: 16, height: 16)
                .background(LairColors.attention, in: Circle())
                .overlay(Circle().strokeBorder(.black.opacity(0.4), lineWidth: 1))
                .transition(.scale.combined(with: .opacity))
        } else if call.unread && !focused {
            Circle().fill(LairColors.unread).frame(width: 9, height: 9).padding(3)
        }
    }

    private var help: String {
        let what = call.questionText != nil ? "asks you something"
            : call.pendingApproval != nil ? "needs your OK"
            : call.unread ? "has news"
            : call.guest ? "on this Mac" : call.inCall ? "on a call" : "not on a call"
        return "\(call.agent.name), \(what)"
    }
}

/// Rings rippling out of an avatar while that agent is the voice you hear.
private struct SpeakingRing: View {
    let tint: Color
    @Environment(\.renderTime) private var renderTime

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = renderTime ?? timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<2) { i in
                    let phase = (time * 0.9 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                    Circle()
                        .strokeBorder(tint.opacity(0.7 * (1 - phase)), lineWidth: 1.5)
                        .scaleEffect(0.7 + phase * 0.42)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Someone other than the agent in front of you is waiting on you: who, and one click to get there.
private struct ElsewhereBar: View {
    let call: Call
    /// Others waiting behind this one.
    let more: Int
    let go: () -> Void

    var body: some View {
        Button(action: go) {
            HStack(spacing: 8) {
                Circle().fill(Color(hex: call.agent.color)).frame(width: 8, height: 8)
                Text(call.questionText != nil ? "\(call.agent.name) asks you something" : "\(call.agent.name) needs your OK")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if more > 0 {
                    Text("+\(more)")
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .foregroundStyle(LairColors.attention)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(LairColors.attention.opacity(0.18), in: Capsule())
                        .help("\(more) more waiting on you")
                }
                Text("Answer")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(LairColors.attention)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(LairColors.attention)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(LairColors.attention.opacity(0.13), in: Capsule())
            .overlay(Capsule().strokeBorder(LairColors.attention.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(call.questionText != nil ? "\(call.agent.name) asks you something; answer" : "\(call.agent.name) needs your OK; answer")
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
                Section("Thinking") {
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
            .font(.caption)
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
                .foregroundStyle(LairColors.problem)
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
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(LairColors.problem)
            Text(text)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
            Spacer(minLength: 4)
            Button(action, action: perform).buttonStyle(PillButtonStyle())
        }
        .padding(10)
        .background(LairColors.problem.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        .frame(height: lines.isEmpty ? (live ? 44 : 0) : 240)
        .frame(maxWidth: .infinity)
        // Older lines scroll away under a clean edge, not a fade.
        .clipped()
        .opacity(lines.isEmpty && !live ? 0 : 1)
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
                    .foregroundStyle(LairColors.problem)
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
    /// Where the glow sits across the panel: over the stage.
    var center = 0.5

    var body: some View {
        // Near black like the island and Mission Control, with only a faint glow behind the orb.
        ZStack {
            Color(red: 0.035, green: 0.037, blue: 0.045)
            RadialGradient(colors: [tint.opacity(live ? 0.2 : 0.1), .clear], center: UnitPoint(x: center, y: 0.2),
                           startRadius: 0, endRadius: 190)
                .animation(.easeInOut(duration: 0.6), value: live)
        }
    }
}

/// Where a guest runs: on this Mac, in its folder.
struct GuestBadge: View {
    let folder: URL?
    var monospaced = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "laptopcomputer").font(.system(size: 10, weight: .semibold))
            Text(["On this Mac", folder?.lastPathComponent].compactMap { $0 }.joined(separator: " · "))
                .font(monospaced ? .system(.caption, design: .monospaced) : .system(.caption, design: .rounded, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.6))
        .help(folder?.path ?? "An agent running on this Mac")
    }
}

/// A guest's question: pick a choice, say the answer, type it, or skip it. The bar empties as the agent's wait
/// runs out.
struct QuestionCard: View {
    let agent: String
    let question: String
    var choices: [String] = []
    /// ⌘1, ⌘2… pick a choice; off where several cards share the window.
    var shortcuts = true
    let since: Date?
    let deadline: Date?
    let tint: Color
    let answer: (String) -> Void
    let skip: () -> Void
    @State private var draft = ""
    @Environment(\.renderTime) private var renderTime

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.bubble.fill").foregroundStyle(tint)
                Text("\(agent) asks").font(.system(.subheadline, design: .rounded, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 6)
                if let since, let deadline {
                    TimeLeft(since: since, deadline: deadline, tint: tint)
                }
            }
            Text(question)
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)
                .help(question)
                .textSelection(.enabled)
            if !choices.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { choiceButtons }
                    VStack(alignment: .leading, spacing: 6) { choiceButtons }
                }
            }
            HStack(spacing: 8) {
                Group {
                    // Text fields don't render offscreen: snapshots get a look-alike.
                    if renderTime == nil {
                        TextField(placeholder, text: $draft).textFieldStyle(.plain).onSubmit(send)
                    } else {
                        Text(placeholder).foregroundStyle(.white.opacity(0.35)).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .font(.system(.callout, design: .rounded))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(.white.opacity(0.08), in: Capsule())
                Button(action: skip) {
                    Text("Skip").padding(.horizontal, 12).padding(.vertical, 7).background(.white.opacity(0.1), in: Capsule())
                }
                .help("Tell \(agent) you won't answer; it carries on")
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 30, height: 30)
                        .background(draft.trimmingCharacters(in: .whitespaces).isEmpty ? .white.opacity(0.3) : .white, in: Circle())
                }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Send your answer to \(agent)")
            }
            .buttonStyle(.plain)
            .font(.system(.callout, design: .rounded))
        }
        .padding(14)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(tint.opacity(0.5), lineWidth: 1))
    }

    private var placeholder: String { choices.isEmpty ? "Type, or just say it" : "Or something else…" }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        answer(text)
    }

    @ViewBuilder private var choiceButtons: some View {
        ForEach(Array(choices.enumerated()), id: \.offset) { index, choice in
            ChoiceButton(number: index + 1, choice: choice, tint: tint, shortcut: shortcuts && index < 9) { answer(choice) }
        }
    }
}

/// One of a question's choices, numbered, with ⌘ and its number as a shortcut where there's one card.
struct ChoiceButton: View {
    let number: Int
    let choice: String
    let tint: Color
    let shortcut: Bool
    let pick: () -> Void

    var body: some View {
        Button(action: pick) { label }
            .buttonStyle(.plain)
            .keyboardShortcut(shortcut ? KeyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: .command) : nil)
            .help(shortcut ? "Answer “\(choice)” (⌘\(number)); or just say it" : "Answer “\(choice)”; or just say it")
            .accessibilityLabel("Answer \(choice)")
    }

    private var label: some View {
        HStack(spacing: 7) {
            Text(String(number))
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .frame(width: 17, height: 17)
                .background(tint.opacity(0.18), in: Circle())
            Text(choice)
                .font(.system(.callout, design: .rounded, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 6).padding(.trailing, 12).padding(.vertical, 6)
        .background(.white.opacity(0.1), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 1))
        .contentShape(Capsule())
    }
}

/// How long a question still waits, as a shrinking bar and the minutes and seconds left.
struct TimeLeft: View {
    let since: Date
    let deadline: Date
    let tint: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let total = max(1, deadline.timeIntervalSince(since))
            let left = max(0, deadline.timeIntervalSince(timeline.date))
            HStack(spacing: 6) {
                Capsule().fill(.white.opacity(0.12))
                    .frame(width: 44, height: 4)
                    .overlay(alignment: .leading) {
                        Capsule().fill(tint).frame(width: 44 * left / total, height: 4)
                    }
                Text(Duration.seconds(left.rounded(.up)).formatted(.time(pattern: .minuteSecond)))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .animation(.linear(duration: 1), value: left)
        }
        .accessibilityLabel("Waits for your answer")
    }
}
