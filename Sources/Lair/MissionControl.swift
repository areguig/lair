import KeyboardShortcuts
import LairCore
import SwiftUI

extension KeyboardShortcuts.Name {
    static let missionControl = Self("missionControl", initial: .init(.l, modifiers: [.option, .command]))
}

/// The geek view: every agent's whole stream side by side, the way a terminal agent shows it, with a line to type in.
struct MissionControl: View {
    static let title = "Lair Mission Control"
    /// Kept by hand rather than as a SwiftUI scene, so the global shortcut can open it from anywhere.
    @MainActor private static var window: NSWindow?

    let room: Room

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.top, 20)
            if room.calls.isEmpty {
                Text("No agents yet. Add one in Settings.")
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(room.calls) { call in
                            AgentColumn(call: call, room: room)
                                .containerRelativeFrame(.horizontal, count: min(room.calls.count, 3), spacing: 14)
                        }
                    }
                    .padding(.vertical, 14)
                }
                // Margins, not padding: the columns size themselves against the visible width.
                .contentMargins(.horizontal, 14, for: .scrollContent)
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .background(
            ZStack {
                Color(red: 0.045, green: 0.05, blue: 0.065)
                RadialGradient(colors: [Color(hex: room.focused?.agent.color ?? "#8A8F98").opacity(0.12), .clear],
                               center: .top, startRadius: 0, endRadius: 700)
            }
            .ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "circle.circle.fill").foregroundStyle(.white.opacity(0.8))
            Text("Mission Control").font(.system(.headline, design: .rounded, weight: .semibold))
            Spacer()
            if let shortcut = TalkKey.shared.label {
                Text("Hold \(shortcut) to talk · type below to write")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Divider().opacity(0.4) }
    }

    /// Opens the window in front, or closes it when it's already in front.
    @MainActor static func toggle(room: Room) {
        if let window, window.isVisible, window.isKeyWindow {
            window.orderOut(nil)
            return
        }
        let window = window ?? {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 780),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = title
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = NSHostingView(rootView: MissionControl(room: room))
            window.setFrameAutosaveName("LairMissionControl")
            if !window.setFrameUsingName("LairMissionControl") { window.center() }
            return window
        }()
        self.window = window
        NSApp.activate()
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }
}

/// One agent's lane: who it is, everything it did, and a line to type to it.
private struct AgentColumn: View {
    let call: Call
    let room: Room
    @State private var draft = ""

    var body: some View {
        let tint = Color(hex: call.agent.color)
        let focused = call.id == room.focusedID
        VStack(spacing: 0) {
            header(tint: tint)
            Divider().overlay(tint.opacity(0.5))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if call.entries.isEmpty {
                        Text("Nothing yet. Talk or type to \(call.agent.name).")
                            .font(.system(.callout, design: .rounded))
                            .foregroundStyle(.white.opacity(0.4))
                            .padding(.top, 30)
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(call.entries) { entry in
                        EntryView(entry: entry, tint: tint)
                    }
                }
                .padding(14)
            }
            .defaultScrollAnchor(.bottom)
            if let request = call.pendingApproval {
                ApprovalCard(agent: call.agent.name, request: request, tint: tint, shortcuts: false) {
                    room.answer(call, decision: $0)
                }
                .padding([.horizontal, .top], 10)
            }
            composer(tint: tint)
        }
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(focused ? tint.opacity(0.7) : .white.opacity(0.08), lineWidth: focused ? 1.5 : 1))
        .shadow(color: focused ? tint.opacity(0.25) : .clear, radius: 18)
        .contentShape(Rectangle())
        .onTapGesture { room.focus(call) }
    }

    private func header(tint: Color) -> some View {
        HStack(spacing: 12) {
            Orb(color: tint, state: call.state, meter: nil)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(call.agent.name).font(.system(.headline, design: .rounded, weight: .semibold))
                Text([call.details, stateText].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer()
            if call.state == .waiting {
                Label("Needs your OK", systemImage: "hand.raised.fill")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            Button { room.toggle(call) } label: {
                Image(systemName: call.inCall ? "phone.down.fill" : "phone.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(call.inCall ? Color(red: 0.92, green: 0.3, blue: 0.3) : Color(red: 0.25, green: 0.75, blue: 0.45),
                                in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(room.readiness != .ready)
            .help(call.inCall ? "Hang up" : "Call \(call.agent.name)")
            .accessibilityLabel(call.inCall ? "Hang up \(call.agent.name)" : "Call \(call.agent.name)")
        }
        .foregroundStyle(.white)
        .padding(12)
    }

    private var stateText: String {
        switch call.state {
        case .offline: "not in a call"
        case .ready: "in a call"
        case .listening where room.answering?.callID == call.id: "listening for your reply"
        case .listening: "listening"
        case .thinking: "working"
        case .speaking: "speaking"
        case .waiting: "waiting for you"
        }
    }

    private func composer(tint: Color) -> some View {
        HStack(spacing: 8) {
            TextField("Write to \(call.agent.name)…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .font(.system(.body, design: .rounded))
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 26, height: 26)
                    .background(draft.isEmpty ? .white.opacity(0.3) : tint, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityLabel("Send to \(call.agent.name)")
        }
        .padding(10)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(10)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        room.type(text, to: call)
    }
}

/// One thing in the stream, drawn the way a terminal agent would show it, only nicer.
private struct EntryView: View {
    let entry: LogEntry
    let tint: Color

    var body: some View {
        switch entry.kind {
        case .you(let text):
            Text(text)
                .textSelection(.enabled)
                .font(.system(.body, design: .rounded))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 40)
        case .agent(let text):
            Text(Self.reading(text))
                .textSelection(.enabled)
                .font(.system(.body))
                .foregroundStyle(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
        case .thinking(let text):
            ThinkingBlock(text: text)
        case .tool(let name, let input, let output, let failed):
            ToolCard(name: name, input: input, output: output, failed: failed, tint: tint)
        case .note(let text):
            Label(text, systemImage: "info.circle")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
        case .problem(let text):
            Label(text, systemImage: "exclamationmark.triangle.fill")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.orange)
                .textSelection(.enabled)
        case .approval(let text):
            Label(text, systemImage: "hand.raised.fill")
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        case .usage(let input, let output, let cost):
            Stats(items: ["\(Self.tokens(input)) in", "\(Self.tokens(output)) out"]
                + (cost.map { [String(format: "$%.3f", $0)] } ?? []))
        case .timing(let heard, let firstWord, let firstSound, let total):
            Stats(items: [heard.map { "heard \(Self.time($0))" }, firstWord.map { "first word \(Self.time($0))" },
                          firstSound.map { "first sound \(Self.time($0))" }, "turn \(Self.time(total))"].compactMap { $0 })
        }
    }

    /// Links and paths in `<show>` tags read as code and links; the rest as the agent's own Markdown.
    static func reading(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: ShowFilter.markdown(text), options: options)) ?? AttributedString(text)
    }

    static func tokens(_ count: Int) -> String {
        count >= 1_000 ? String(format: "%.1fk", Double(count) / 1_000) : "\(count)"
    }

    static func time(_ ms: Int) -> String {
        ms >= 1_000 ? String(format: "%.1f s", Double(ms) / 1_000) : "\(ms) ms"
    }
}

/// The agent's reasoning, dimmed and folded to its start until you open it.
private struct ThinkingBlock: View {
    let text: String
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { withAnimation(.smooth(duration: 0.2)) { open.toggle() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain").font(.caption)
                    Text("Thinking").font(.system(.caption, design: .rounded, weight: .semibold))
                    Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            Text(text)
                .font(.system(.callout, design: .serif).italic())
                .foregroundStyle(.white.opacity(0.48))
                .lineLimit(open ? nil : 2)
                .textSelection(.enabled)
        }
        .padding(.leading, 10)
        .overlay(alignment: .leading) { Rectangle().fill(.white.opacity(0.12)).frame(width: 2) }
    }
}

/// A tool call as a card: what ran, on what, and how it went; the output folds open, diffs in color.
private struct ToolCard: View {
    let name: String
    let input: String
    let output: String?
    let failed: Bool
    let tint: Color
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { if output?.isEmpty == false { withAnimation(.smooth(duration: 0.2)) { open.toggle() } } } label: {
                HStack(spacing: 8) {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 18)
                    Text(name).font(.system(.caption, design: .monospaced, weight: .semibold))
                    Text(input)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 6)
                    status
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(input)
            if open, let output, !output.isEmpty {
                Divider().opacity(0.3)
                ScrollView {
                    Output(text: output)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 240)
            }
        }
        .foregroundStyle(.white.opacity(0.9))
        .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(failed ? .red.opacity(0.5) : .white.opacity(0.08)))
    }

    @ViewBuilder private var status: some View {
        if output == nil {
            ProgressView().controlSize(.mini)
        } else if failed {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        } else {
            Image(systemName: open ? "chevron.up" : "checkmark.circle.fill")
                .foregroundStyle(open ? .white.opacity(0.5) : .green.opacity(0.85))
        }
    }

    private var symbol: String {
        switch name {
        case "Bash", "bash", "terminal", "exec": "terminal"
        case "Read", "read": "doc.text"
        case "Write", "Edit", "MultiEdit", "edit", "write", "NotebookEdit": "pencil"
        case "Grep", "Glob", "grep", "find", "search": "magnifyingglass"
        case "WebFetch", "WebSearch", "web_search", "fetch": "globe"
        case "Task", "Agent", "task", "delegate_task": "person.2"
        default: "wrench.and.screwdriver"
        }
    }
}

/// Tool output in monospace; diff lines get their colors.
private struct Output: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(text.split(separator: "\n", omittingEmptySubsequences: false).prefix(400).enumerated()),
                    id: \.offset) { _, line in
                Text(line.isEmpty ? " " : String(line))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(color(for: line))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(background(for: line))
            }
        }
        .textSelection(.enabled)
    }

    private func color(for line: Substring) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return Color(red: 0.55, green: 0.9, blue: 0.6) }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return Color(red: 1, green: 0.55, blue: 0.55) }
        if line.hasPrefix("@@") { return Color(red: 0.55, green: 0.7, blue: 1) }
        return .white.opacity(0.78)
    }

    private func background(for line: Substring) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return .green.opacity(0.08) }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return .red.opacity(0.08) }
        return .clear
    }
}

/// A quiet row of small facts: timings, tokens, cost.
private struct Stats: View {
    let items: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.white.opacity(0.06), in: Capsule())
            }
        }
    }
}
