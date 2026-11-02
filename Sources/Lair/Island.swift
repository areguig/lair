import AppKit
import LairCore
import LairVoice
import SwiftUI

/// Lair at the top of the screen, grown out of the notch (or hung under the menu bar on a screen without one).
/// Quiet, it's invisible; on a call it grows ears with the agent's orb; while someone speaks or listens it shows
/// the words; when someone needs you it drops down with the question or the OK. It never takes focus, and clicks
/// go through it everywhere but the island itself.
@MainActor final class Island {
    /// The transparent panel the island is drawn in, at the top center of the screen.
    static let canvas = NSSize(width: 640, height: 340)

    private let room: Room
    private let model = IslandModel()
    private let panel = NSPanel(contentRect: NSRect(origin: .zero, size: Island.canvas),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    private var pointer: Timer?
    private var screenObserver: NSObjectProtocol?

    init(room: Room) {
        self.room = room
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Above the menu bar, so it can grow out of the notch.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: IslandView(room: room, model: model))
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.place() } }
    }

    /// From the config's `island` setting.
    var isOn = false {
        didSet {
            guard isOn != oldValue else { return }
            if isOn { show() } else { hide() }
        }
    }

    private func show() {
        place()
        panel.orderFrontRegardless()
        // Windows can't be shaped for clicks, so the panel ignores the mouse unless it's over the island.
        pointer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.followPointer() }
        }
    }

    private func hide() {
        panel.orderOut(nil)
        pointer?.invalidate()
        pointer = nil
    }

    /// The screen with a notch if there is one, else the main one.
    private func place() {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
        let frame = screen.frame
        if screen.safeAreaInsets.top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            model.metrics = .init(notch: true, width: frame.width - left.width - right.width, height: screen.safeAreaInsets.top,
                                  top: 0)
        } else {
            model.metrics = .init(notch: false, width: 0, height: 0, top: frame.maxY - screen.visibleFrame.maxY + 6)
        }
        panel.setFrameOrigin(NSPoint(x: frame.midX - Self.canvas.width / 2, y: frame.maxY - Self.canvas.height))
    }

    private func followPointer() {
        guard NSEvent.pressedMouseButtons == 0 else { return }
        let mouse = NSEvent.mouseLocation, frame = panel.frame, size = model.size
        let island = NSRect(x: frame.midX - size.width / 2, y: frame.maxY - model.metrics.top - size.height,
                            width: size.width, height: size.height)
        let inside = size.width > 0 && island.contains(mouse)
        panel.ignoresMouseEvents = !inside
        if model.hovering != inside { model.hovering = inside }
    }
}

/// What the view and its window share: the notch's shape, the island's drawn size, and whether the pointer's on it.
@Observable @MainActor final class IslandModel {
    struct Metrics: Equatable {
        /// On a screen with a notch the island grows out of it; elsewhere it hangs under the menu bar.
        var notch: Bool
        var width: CGFloat
        var height: CGFloat
        /// From the top of the screen to the top of the island.
        var top: CGFloat
    }

    var metrics = Metrics(notch: true, width: 200, height: 32, top: 0)
    var size = CGSize.zero
    var hovering = false
}

struct IslandView: View {
    let room: Room
    let model: IslandModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    private enum Mode: Equatable {
        case hidden, resting, live, asking, approving
    }

    /// Who the island is about: whoever needs you first, else the agent in focus.
    private var subject: Call? { room.calls.first { $0.awaitsYou && $0.id == room.focusedID } ?? room.calls.first(where: \.awaitsYou) ?? room.focused }

    private var mode: Mode {
        guard let call = subject else { return .hidden }
        if call.questionText != nil { return .asking }
        if call.pendingApproval != nil { return .approving }
        if call.state == .speaking || call.state == .listening || room.answering != nil || reading(call) { return .live }
        guard room.calls.contains(where: { $0.inCall }) else { return .hidden }
        return model.hovering ? .live : .resting
    }

    var body: some View {
        VStack(spacing: 0) {
            island
                .onGeometryChange(for: CGSize.self) { $0.size } action: { model.size = $0 }
            Spacer(minLength: 0)
        }
        .padding(.top, model.metrics.top)
        .frame(width: Island.canvas.width, height: Island.canvas.height)
        .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.82), value: mode)
        .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.82), value: subject?.id)
        .environment(\.colorScheme, .dark)
        // Someone who isn't looking at the screen still hears that they're needed.
        .onChange(of: announcement) { _, text in
            if let text { AccessibilityNotification.Announcement(text).post() }
        }
    }

    /// What VoiceOver says when someone starts needing you.
    private var announcement: String? {
        mode == .asking || mode == .approving ? summary(subject) : nil
    }

    /// Secondary text, stronger when the person asked for more contrast.
    private func dim(_ opacity: Double) -> Color { .white.opacity(contrast == .increased ? max(opacity, 0.85) : opacity) }

    @ViewBuilder private var island: some View {
        let metrics = model.metrics
        let call = subject
        let tint = call.map { Color(hex: $0.agent.color) } ?? .white
        let shape = IslandShape(notch: metrics.notch, radius: mode == .resting ? 12 : 24)
        VStack(spacing: 0) {
            // Below the notch, the content's own top padding would leave too wide a gap.
            if metrics.notch { Color.clear.frame(height: mode == .resting ? 0 : max(0, metrics.height - 8)) }
            if let call {
                switch mode {
                case .hidden: EmptyView()
                case .resting: ears(call, tint: tint)
                case .live: live(call, tint: tint)
                case .asking: asking(call, tint: tint)
                case .approving: approving(call, tint: tint)
                }
            }
        }
        .frame(width: width(for: mode))
        .background(shape.fill(.black))
        .overlay(shape.stroke(.white.opacity(metrics.notch ? 0 : 0.12), lineWidth: 1))
        .clipShape(shape)
        .shadow(color: .black.opacity(mode == .resting || mode == .hidden ? 0 : 0.45), radius: 18, y: 8)
        .opacity(mode == .hidden ? 0 : 1)
        .contentShape(shape)
        .accessibilityElement(children: mode == .asking || mode == .approving ? .contain : .combine)
        .accessibilityLabel(summary(call))
        .accessibilityHidden(mode == .hidden)
    }

    /// Who, and what they're doing or asking.
    private func summary(_ call: Call?) -> String {
        guard let call else { return "" }
        switch mode {
        case .asking: return "\(call.agent.name) asks: \(call.questionText ?? "")"
        case .approving: return "\(call.agent.name) needs your OK: \(call.pendingApproval?.summary ?? "")"
        case .live: return "\(call.agent.name), \(call.state.label): \(caption(call))"
        default: return "\(call.agent.name), \(call.state.label)" + (room.silent ? ", silent mode" : "")
        }
    }

    private func width(for mode: Mode) -> CGFloat {
        let notch = model.metrics.notch ? model.metrics.width : 0
        switch mode {
        case .hidden: return model.metrics.notch ? notch : 120
        case .resting: return model.metrics.notch ? notch + 92 : 150
        case .live: return max(notch + 160, 400)
        case .asking, .approving: return max(notch + 180, 430)
        }
    }

    // MARK: Modes

    /// The orb on the left of the notch, clicked to talk; on its right, whether anyone needs you or is working.
    private func ears(_ call: Call, tint: Color) -> some View {
        let waiting = room.calls.filter(\.awaitsYou).count
        let working = room.calls.contains { $0.state == .thinking }
        return HStack(spacing: 0) {
            Orb(color: tint, state: call.state, meter: room.meter(for: call))
                .frame(width: 20, height: 20)
                .frame(width: 46)
                .contentShape(Rectangle())
                .onTapGesture { room.toggleTalk() }
                .help("\(call.agent.name): click to talk")
                .accessibilityLabel("Talk to \(call.agent.name)")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { room.toggleTalk() }
            Spacer(minLength: model.metrics.notch ? model.metrics.width : 8)
            HStack(spacing: 4) {
                if room.silent { silentMark }
                if waiting > 0 {
                    Text("\(waiting)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(width: 18, height: 18)
                        .background(LairColors.attention, in: Circle())
                } else if working {
                    WorkingDots(tint: tint, animated: !reduceMotion)
                } else {
                    Circle().fill(tint.opacity(0.8)).frame(width: 6, height: 6)
                }
            }
            .frame(width: 46)
        }
        .frame(height: max(model.metrics.height, 30))
    }

    /// Who's talking and what they're saying, or that Lair is listening to you.
    private func live(_ call: Call, tint: Color) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Orb(color: tint, state: call.state, meter: room.meter(for: call))
                .frame(width: 34, height: 34)
                .contentShape(Circle())
                .onTapGesture { room.toggleTalk() }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(call.agent.name).font(.system(.caption, design: .rounded, weight: .bold)).foregroundStyle(tint)
                    if room.silent { silentMark }
                    if call.guest { Image(systemName: "laptopcomputer").font(.system(size: 9)).foregroundStyle(dim(0.45)).accessibilityLabel("On this Mac") }
                }
                Text(caption(call))
                    .font(.system(.callout, design: .rounded, weight: .medium))
                    .foregroundStyle(dim(0.92))
                    .lineLimit(2)
                    .truncationMode(.head)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 0)
            if call.state == .listening {
                ListeningBars(meter: room.meter(for: call), tint: tint, animated: !reduceMotion)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    /// Nothing is said in silent mode, so the answer is shown as it arrives.
    private func reading(_ call: Call) -> Bool {
        room.silent && call.state == .thinking && call.lines.last?.role == .agent
    }

    private var silentMark: some View {
        Image(systemName: "speaker.slash.fill").font(.system(size: 9)).foregroundStyle(dim(0.5)).accessibilityLabel("Silent mode")
    }

    /// While speaking, the sentence being said; otherwise the agent's last line.
    private func caption(_ call: Call) -> String {
        switch call.state {
        case .listening: return room.answering?.callID == call.id ? "Listening for your answer…" : "Listening…"
        case .thinking where !reading(call): return "\(CallState.thinking.label)…"
        case .speaking where call.id == room.focusedID && room.speaking != nil: return room.speaking ?? ""
        default:
            let said = call.lines.last { $0.role == .agent }?.text ?? ""
            return said.isEmpty ? (call.guest ? "Working on its own" : "In a call") : said
        }
    }

    private func asking(_ call: Call, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(call, tint: tint, title: "\(call.agent.name) asks") {
                if let since = call.questionSince, let deadline = call.questionDeadline {
                    TimeLeft(since: since, deadline: deadline, tint: tint)
                }
            }
            Text(call.questionText ?? "")
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(4)
            if !call.questionChoices.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { choices(call, tint: tint) }
                    VStack(alignment: .leading, spacing: 6) { choices(call, tint: tint) }
                }
            }
            HStack {
                Label("Say it, or hold \(TalkKey.shared.label ?? "the talk key")", systemImage: "mic.fill")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(dim(0.5))
                Spacer()
                Button("Skip") { room.skipQuestion(of: call) }
                    .buttonStyle(IslandButtonStyle(fill: .white.opacity(0.12), strongFill: .white.opacity(0.3)))
            }
        }
        .padding(16)
    }

    @ViewBuilder private func choices(_ call: Call, tint: Color) -> some View {
        ForEach(Array(call.questionChoices.enumerated()), id: \.offset) { index, choice in
            ChoiceButton(number: index + 1, choice: choice, tint: tint, shortcut: false) {
                room.answerQuestion(of: call, with: choice)
            }
        }
    }

    private func approving(_ call: Call, tint: Color) -> some View {
        let request = call.pendingApproval
        return VStack(alignment: .leading, spacing: 10) {
            header(call, tint: tint, title: "\(call.agent.name) needs your OK") {
                Text(request?.tool ?? "").font(.system(.caption2, design: .monospaced)).foregroundStyle(dim(0.55))
            }
            Text(request?.summary ?? "")
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(4)
            HStack(spacing: 8) {
                Button("Deny") { room.answer(call, decision: .deny) }
                    .buttonStyle(IslandButtonStyle(fill: .white.opacity(0.12), strongFill: .white.opacity(0.3)))
                if request?.canAlwaysAllow == true {
                    Button("Always allow") { room.answer(call, decision: .allowAlways) }
                        .buttonStyle(IslandButtonStyle(fill: tint.opacity(0.3), strongFill: tint.opacity(0.6)))
                }
                Spacer()
                Button("Allow") { room.answer(call, decision: .allowOnce) }
                    .buttonStyle(IslandButtonStyle(fill: .white, text: .black))
            }
        }
        .padding(16)
    }

    private func header<Trailing: View>(_ call: Call, tint: Color, title: String,
                                        @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 8) {
            Orb(color: tint, state: call.state, meter: room.meter(for: call)).frame(width: 22, height: 22)
            Text(title).font(.system(.subheadline, design: .rounded, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
            if let folder = call.folder, call.guest {
                Text(folder.lastPathComponent).font(.caption).foregroundStyle(dim(0.6))
            }
            Spacer(minLength: 6)
            trailing()
        }
    }
}

/// Square on top where it meets the screen's edge, rounded below; on a screen without a notch, rounded all round.
private struct IslandShape: Shape {
    let notch: Bool
    var radius: CGFloat

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        guard notch else { return RoundedRectangle(cornerRadius: min(radius, rect.height / 2), style: .continuous).path(in: rect) }
        let r = min(radius, rect.height / 2, rect.width / 2)
        return UnevenRoundedRectangle(bottomLeadingRadius: r, bottomTrailingRadius: r, style: .continuous).path(in: rect)
    }
}

private struct IslandButtonStyle: ButtonStyle {
    var fill: Color
    /// The fill when the person asked for more contrast.
    var strongFill: Color? = nil
    var text: Color = .white
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        let fill = contrast == .increased ? strongFill ?? fill : fill
        return configuration.label
            .font(.system(.callout, design: .rounded, weight: .semibold))
            .foregroundStyle(text)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(fill.opacity(configuration.isPressed ? 0.7 : 1), in: Capsule())
    }
}

/// Three dots taking turns while an agent works.
private struct WorkingDots: View {
    let tint: Color
    let animated: Bool
    @Environment(\.renderTime) private var renderTime

    var body: some View {
        TimelineView(.animation(paused: !animated)) { timeline in
            let time = renderTime ?? timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<3) { i in
                    Circle().fill(tint)
                        .frame(width: 4, height: 4)
                        .opacity(0.35 + 0.65 * max(0, sin(time * 5 - Double(i) * 0.9)))
                }
            }
        }
        .accessibilityLabel("Working")
    }
}

/// Your voice as a few bars, while Lair listens.
private struct ListeningBars: View {
    let meter: LevelMeter?
    let tint: Color
    let animated: Bool
    @Environment(\.renderTime) private var renderTime

    var body: some View {
        TimelineView(.animation(paused: !animated)) { timeline in
            let time = renderTime ?? timeline.date.timeIntervalSinceReferenceDate
            let level = Double(meter?.level ?? 0)
            HStack(spacing: 3) {
                ForEach(0..<5) { i in
                    Capsule().fill(tint)
                        .frame(width: 3, height: 6 + 18 * min(1, level * 1.6) * (0.5 + 0.5 * abs(sin(time * 9 + Double(i)))))
                }
            }
            .frame(height: 26)
        }
        .accessibilityLabel("Listening")
    }
}
