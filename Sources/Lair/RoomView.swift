import KeyboardShortcuts
import LairCore
import LairVoice
import OSLog
import ServiceManagement
import SwiftUI

/// The menu-bar panel: the focused agent's orb, what was said, and the call controls.
struct RoomView: View {
    let room: Room
    @Environment(\.openWindow) private var openWindow
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        let call = room.focused
        let tint = call.map { Color(hex: $0.agent.color) } ?? .gray
        VStack(spacing: 0) {
            header
            if let call {
                stage(call, tint: tint)
                if room.calls.count > 1 { roster.padding(.top, 14) }
                Transcript(lines: call.lines).padding(.top, 18)
                if let request = call.pendingApproval {
                    ApprovalCard(agent: call.agent.name, request: request, tint: tint,
                                 answer: { room.answer(call, decision: $0) })
                        .padding(.top, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                controls(call, tint: tint).padding(.top, 14)
            }
            footer.padding(.top, 14)
        }
        .padding(18)
        .frame(width: 340)
        .animation(.smooth(duration: 0.3), value: call?.pendingApproval)
        .background(Backdrop(tint: tint, live: call?.inCall == true))
        .environment(\.colorScheme, .dark)
    }

    private func setOpensAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "lair", category: "login").error("\(error)")
        }
        opensAtLogin = SMAppService.mainApp.status == .enabled
    }

    private var header: some View {
        HStack {
            Text("Lair")
                .font(.system(.headline, design: .rounded, weight: .semibold))
            Spacer()
            Menu {
                Button("Push-to-Talk Shortcut…") {
                    openWindow(id: ShortcutWindow.id)
                    NSApp.activate()
                }
                Button("Open Config…") { NSWorkspace.shared.open(LairConfig.defaultURL) }
                Toggle("Open at Login", isOn: Binding(get: { opensAtLogin }, set: setOpensAtLogin))
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
        }
        .foregroundStyle(.white.opacity(0.9))
    }

    private func stage(_ call: Call, tint: Color) -> some View {
        VStack(spacing: 14) {
            Orb(color: tint, state: call.state, meter: meter(for: call))
                .frame(width: 112, height: 112)
                .frame(height: 150)
                .contentShape(Circle())
                .onTapGesture { room.toggle(call) }
            VStack(spacing: 4) {
                Text(call.agent.name)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                if let details = call.details {
                    Text(details)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .transition(.opacity)
                }
                Text(caption(for: call))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: caption(for: call))
            }
        }
        .padding(.top, 4)
    }

    private var roster: some View {
        HStack(spacing: 10) {
            ForEach(room.calls) { call in
                Button { room.focus(call) } label: {
                    HStack(spacing: 6) {
                        StatusDot(color: Color(hex: call.agent.color), state: call.state)
                        Text(call.agent.name).font(.system(.caption, design: .rounded, weight: .medium))
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
            }
        }
    }

    private func controls(_ call: Call, tint: Color) -> some View {
        HStack(spacing: 28) {
            RoundButton(symbol: call.inCall ? "phone.down.fill" : "phone.fill",
                        fill: call.inCall ? Color(red: 0.92, green: 0.3, blue: 0.3) : Color(red: 0.25, green: 0.75, blue: 0.45),
                        size: 44) { room.toggle(call) }
                .help(call.inCall ? "Hang up" : "Call \(call.agent.name)")
            HoldToTalk(active: call.state == .listening, tint: tint,
                       onPress: room.pressTalk, onRelease: room.releaseTalk)
                .disabled(room.readiness != .ready)
            RoundButton(symbol: "folder", fill: .white.opacity(0.1), size: 44) {
                if let url = call.agent.directoryURL { NSWorkspace.shared.open(url) }
            }
            .help(call.agent.directory ?? "")
            // Kept in the layout so the talk button stays centered.
            .opacity(call.agent.directoryURL == nil ? 0 : 1)
            .disabled(call.agent.directoryURL == nil)
        }
    }

    @ViewBuilder private var footer: some View {
        if let shortcut = KeyboardShortcuts.getShortcut(for: .pushToTalk) {
            HStack(spacing: 6) {
                Text("Hold")
                Text(shortcut.description)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                Text("anywhere to talk")
            }
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(.white.opacity(0.45))
        }
    }

    private func meter(for call: Call) -> LevelMeter? {
        switch call.state {
        case .listening: room.meterOverride ?? room.microphone.meter
        case .speaking: room.meterOverride ?? room.speaker?.meter
        default: nil
        }
    }

    private func caption(for call: Call) -> String {
        switch room.readiness {
        case .loading: return "Waking up the voices…"
        case .failed(let message): return message
        case .ready: break
        }
        switch call.state {
        case .offline: return "Tap the orb or hold to talk"
        case .ready: return "Listening when you hold"
        case .listening: return "Listening…"
        case .thinking: return "Thinking…"
        case .speaking: return "Speaking"
        case .waiting: return call.pendingApproval?.canAlwaysAllow == true ? "Your OK? Say yes, always or no" : "Your OK? Say yes or no"
        }
    }
}

/// What was said in this call, newest at the bottom, fading out at the top.
private struct Transcript: View {
    let lines: [Call.Line]
    @Environment(\.renderTime) private var renderTime

    var body: some View {
        Group {
            if renderTime == nil {
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
        .frame(height: lines.isEmpty ? 0 : 150)
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.18),
                                     .init(color: .black, location: 1)], startPoint: .top, endPoint: .bottom))
        .animation(.smooth, value: lines.isEmpty)
    }

    @ViewBuilder private func row(_ line: Call.Line) -> some View {
        switch line.role {
        case .you:
            Text(line.text)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 40)
        case .agent:
            Text(line.text.isEmpty ? "…" : line.text)
                .foregroundStyle(.white.opacity(0.88))
                .padding(.trailing, 24)
        case .notice:
            Label(line.text, systemImage: "exclamationmark.circle")
                .font(.caption)
                .foregroundStyle(.orange.opacity(0.9))
        }
    }
}

/// What the agent wants to do, with the same Allow and Deny as the notification and your voice.
private struct ApprovalCard: View {
    let agent: String
    let request: ApprovalRequest
    let tint: Color
    let answer: (ApprovalDecision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill").foregroundStyle(tint)
                Text("\(agent) needs your OK").font(.system(.subheadline, design: .rounded, weight: .semibold))
                Spacer()
                Text(request.tool)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Text(request.summary)
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button { answer(.deny) } label: {
                    Text("Deny").frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(.white.opacity(0.1), in: Capsule())
                }
                if request.canAlwaysAllow {
                    Button { answer(.allowAlways) } label: {
                        Text("Always").fontWeight(.semibold).foregroundStyle(tint)
                            .frame(maxWidth: .infinity).padding(.vertical, 7)
                            .background(tint.opacity(0.22), in: Capsule())
                    }
                }
                Button { answer(.allowOnce) } label: {
                    Text("Allow").fontWeight(.semibold).foregroundStyle(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(.white, in: Capsule())
                }
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
    let onPress: () -> Void
    let onRelease: () -> Void
    @State private var pressed = false

    var body: some View {
        Image(systemName: "mic.fill")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(active ? .black : .white)
            .frame(width: 64, height: 64)
            .background(active ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.14)), in: Circle())
            .overlay(Circle().strokeBorder(tint.opacity(active ? 0.9 : 0), lineWidth: 3).padding(-5))
            .scaleEffect(pressed ? 0.94 : 1)
            .animation(.spring(duration: 0.25), value: pressed)
            .animation(.easeOut(duration: 0.2), value: active)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if !pressed { pressed = true; onPress() } }
                .onEnded { _ in pressed = false; onRelease() })
            .help("Hold to talk")
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
