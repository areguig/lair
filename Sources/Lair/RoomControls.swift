import LairCore
import SwiftUI

/// One agent in the sidebar: its orb in its own color, alive with its state, its name and where the call is.
struct SidebarRow: View {
    let call: Call
    let focused: Bool
    let select: () -> Void

    var body: some View {
        let tint = Color(hex: call.agent.color)
        Button(action: select) {
            HStack(spacing: 6) {
                ZStack {
                    Orb(color: tint, state: call.state, offlineSaturation: 0.55).frame(width: 26, height: 26)
                    if call.state == .speaking { SpeakingRing(tint: tint) }
                }
                .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text(call.agent.name)
                        .font(.system(.callout, design: .rounded, weight: focused ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(status)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(statusStyle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 0)
                if call.unread && !focused && !call.awaitsYou {
                    Circle().fill(LairColors.unread).frame(width: 8, height: 8)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
            .background(Color.accentColor.opacity(focused ? 0.25 : 0), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(call.agent.name)
        .accessibilityValue(summary)
    }

    private var status: String { call.atKeyboard != nil ? "At keyboard" : call.state.label }

    private var statusStyle: AnyShapeStyle {
        if call.awaitsYou { return AnyShapeStyle(LairColors.attention) }
        return call.state == .speaking || call.state == .listening ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary)
    }

    private var help: String {
        let what = call.questionText != nil ? "asks you something"
            : call.pendingApproval != nil ? "needs your OK"
            : call.unread ? "has news"
            : call.guest ? "on this Mac" : call.inCall ? "on a call" : "not on a call"
        return "\(call.agent.name), \(what)"
    }

    /// What VoiceOver adds to the name: where the call is, and what the agent wants from you.
    private var summary: String {
        let wants = call.questionText != nil ? "asks you something" : call.pendingApproval != nil ? nil : call.unread ? "has news" : nil
        return [status, wants, call.guest ? "on this Mac" : nil].compactMap { $0 }.joined(separator: ", ")
    }
}

/// Rings rippling out of an avatar while that agent is the voice you hear.
private struct SpeakingRing: View {
    let tint: Color
    @Environment(\.renderTime) private var renderTime
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let time = reduceMotion ? 0.3 : renderTime ?? timeline.date.timeIntervalSinceReferenceDate
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

/// The model beside the name, during a call: click it to switch model or thinking for this call.
struct ModelSwitcher: View {
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
                // Local model names can be long: cut in the middle so the start and the thinking level stay.
                Text(call.details ?? "Choose model")
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .controlSurface(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: false, vertical: true)
        .help("Switch model or thinking for this call — or just say “switch to Opus”, “think harder”")
        .accessibilityLabel("\(call.agent.name) model: \(call.details ?? "default"). Switch model or thinking")
        .accessibilityValue(call.state.label)
    }

    private func run(_ command: VoiceCommand) {
        Task { await room.run(command, in: call) }
    }
}

/// Small rounded buttons used for actions inside the panel.
struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.primary.opacity(configuration.isPressed ? 0.24 : 0.14), in: Capsule())
            .outlined(Capsule(), opacity: 0)
    }
}

/// Press and hold to talk; the ring lights up while listening.
struct HoldToTalk: View {
    let active: Bool
    let tint: Color
    var answering: Room.Answering?
    var size: CGFloat = 64
    let onPress: () -> Void
    let onRelease: () -> Void
    @State private var pressed = false

    var body: some View {
        Image(systemName: "mic.fill")
            .font(.system(size: size * 0.34, weight: .semibold))
            .foregroundStyle(active ? Color.inverse : .primary)
            .frame(width: size, height: size)
            .background(active ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.primary.opacity(0.14)), in: Circle())
            .outlined(Circle(), opacity: 0)
            .overlay {
                if let answering {
                    ReplyCountdown(answering: answering, tint: tint, lineWidth: 3).padding(-5)
                } else {
                    Circle().strokeBorder(tint.opacity(active ? 0.9 : 0), lineWidth: 3).padding(-5)
                }
            }
            .scaleEffect(pressed ? 0.94 : 1)
            .motion(.spring(duration: 0.25), value: pressed)
            .motion(.easeOut(duration: 0.2), value: active)
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

/// The window's own background with a soft glow of the agent's color, brighter during a call.
struct Backdrop: View {
    let tint: Color
    let live: Bool
    /// Where the glow sits across the panel: over the stage.
    var center = 0.5

    var body: some View {
        // Opaque, so Reduce Transparency changes nothing here; only a faint glow behind the orb.
        ZStack {
            Color.inverse
            RadialGradient(colors: [tint.opacity(live ? 0.2 : 0.1), .clear], center: UnitPoint(x: center, y: 0.2),
                           startRadius: 0, endRadius: 190)
                .motion(.easeInOut(duration: 0.6), value: live)
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
        .foregroundStyle(.secondary)
        .help(folder?.path ?? "An agent running on this Mac")
    }
}
