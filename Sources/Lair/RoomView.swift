import KeyboardShortcuts
import LairCore
import LairVoice
import SwiftUI

/// The menu-bar panel: the focused agent's orb, what was said, and the call controls.
struct RoomView: View {
    let room: Room
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let call = room.focused
        let tint = call.map { Color(hex: $0.agent.color) } ?? .gray
        VStack(spacing: 0) {
            header
            if let call {
                stage(call, tint: tint)
                if room.calls.count > 1 { roster.padding(.top, 14) }
                Transcript(lines: call.lines).padding(.top, 18)
                controls(call, tint: tint).padding(.top, 14)
            }
            footer.padding(.top, 14)
        }
        .padding(18)
        .frame(width: 340)
        .background(Backdrop(tint: tint, live: call?.inCall == true))
        .environment(\.colorScheme, .dark)
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
                Button { room.focusedID = call.id } label: {
                    HStack(spacing: 6) {
                        Circle().fill(Color(hex: call.agent.color)).frame(width: 8, height: 8)
                            .opacity(call.inCall ? 1 : 0.45)
                        Text(call.agent.name).font(.system(.caption, design: .rounded, weight: .medium))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.white.opacity(call.id == room.focusedID ? 0.14 : 0.05), in: Capsule())
                }
                .buttonStyle(.plain)
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
            .help(call.agent.directory ?? "No folder")
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
        case .listening: room.microphone.meter
        case .speaking: room.speaker?.meter
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
        }
    }
}

/// What was said in this call, newest at the bottom, fading out at the top.
private struct Transcript: View {
    let lines: [Call.Line]

    var body: some View {
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
