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
        .motion(.smooth(duration: 0.3), value: call?.pendingApproval)
        .motion(.smooth(duration: 0.3), value: call?.questionText)
        .motion(.smooth(duration: 0.3), value: room.focusedID)
        .motion(.smooth(duration: 0.3), value: room.calls.map(\.id))
        .background(Backdrop(tint: tint, live: call?.inCall == true, center: call == nil ? 0.5 : 0.6))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Lair")
                .font(.system(.headline, design: .rounded, weight: .semibold))
            if let presence {
                Text(presence)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Spacer()
            if let updates, let version = updates.reminder.version {
                Button { updates.install() } label: {
                    Text("Update")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .padding(.horizontal, 10).frame(height: 26)
                        .controlSurface(Capsule())
                }
                .buttonStyle(.plain)
                .help("Lair \(version) is ready to install")
                .accessibilityLabel("Install Lair \(version)")
            }
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
                    .controlSurface(Circle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More")
        }
        .foregroundStyle(.primary)
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
                    Capsule().fill(.separator).frame(width: 28, height: 1)
                    Text("This Mac")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .textCase(.uppercase)
                        .kerning(0.6)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .help("Sessions on this Mac that aren't one of your agents")
                ForEach(guests) { avatar($0) }
            }
            Button { openSettings(agents.isEmpty ? .mac : .agents) } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .overlay(Circle().strokeBorder(.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Add an agent, or connect the ones you run on this Mac")
            .accessibilityLabel("Add an agent")
            .padding(.top, 4)
        }
        .padding(.vertical, 10)
        .frame(width: 68)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .outlined(RoundedRectangle(cornerRadius: 20, style: .continuous), opacity: 0.08)
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
        .motion(.smooth(duration: 0.3), value: room.calls.contains { $0.id != call.id && $0.awaitsYou })
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
                .accessibilityLabel("\(call.agent.name), \(call.state.label)")
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
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Color.primary.opacity(0.1), in: Capsule())
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
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .transition(.opacity)
                }
                status(for: call)
            }
        }
        .motion(.smooth(duration: 0.3), value: compact)
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
                .foregroundStyle(room.hint == nil ? .secondary : .primary)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
                .motion(.easeInOut(duration: 0.2), value: text)
        }
    }

    /// The talk button in the middle; on its left the call button, or Dismiss for a guest; Mission Control on its right.
    private func controls(_ call: Call) -> some View {
        HStack(spacing: 26) {
            if call.guest {
                // A guest isn't called or hung up: it comes and goes on its own, and can be sent away.
                RoundButton(symbol: "xmark", tint: nil, size: 42) { room.toggle(call) }
                    .help("Dismiss \(call.agent.name); it comes back when it next talks to you")
                    .accessibilityLabel("Dismiss \(call.agent.name)")
                    .accessibilityValue(call.state.label)
            } else {
                RoundButton(symbol: call.inCall ? "phone.down.fill" : "phone.fill",
                            tint: call.inCall ? LairColors.hangUp : LairColors.call,
                            size: 42) { room.toggle(call) }
                    .disabled(room.readiness != .ready)
                    .help(call.inCall ? "Hang up" : "Call \(call.agent.name)")
                    .accessibilityLabel(call.inCall ? "Hang up \(call.agent.name)" : "Call \(call.agent.name)")
                    .accessibilityValue(call.state.label)
            }
            let deaf = call.guest && call.questionText == nil
            HoldToTalk(active: call.state == .listening, tint: Color(hex: call.agent.color),
                       answering: room.answering?.callID == call.id ? room.answering : nil,
                       onPress: room.pressTalk, onRelease: room.releaseTalk)
                .disabled(room.readiness != .ready || deaf)
                .opacity(deaf ? 0.35 : 1)
                .help(deaf ? "\(call.agent.name) listens when it asks you something" : "Hold to talk")
            RoundButton(symbol: "rectangle.split.3x1", tint: nil, size: 42) {
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
                        .frame(maxWidth: 220).padding(.vertical, 8)
                        .background(.primary, in: Capsule())
                }
                Button { openSettings(.mac) } label: {
                    Label("Connect agents on this Mac…", systemImage: "laptopcomputer")
                        .font(.system(.callout, design: .rounded, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: 220).padding(.vertical, 8)
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
