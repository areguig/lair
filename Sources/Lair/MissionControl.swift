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

    /// Your agents only: a session that isn't one of them lives in the panel while it's connected.
    private var agents: [Call] { room.calls.filter { !$0.stranger } }

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.top, 20)
            if agents.isEmpty {
                Text("No agents yet. Add one in Settings.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(agents) { call in
                            AgentColumn(call: call, room: room)
                                .containerRelativeFrame(.horizontal, count: min(agents.count, 3), spacing: 14)
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
                Color(nsColor: .windowBackgroundColor)
                RadialGradient(colors: [Color(hex: room.focused?.agent.color ?? "#8A8F98").opacity(0.12), .clear],
                               center: .top, startRadius: 0, endRadius: 700)
            }
            .ignoresSafeArea())
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "circle.circle.fill").foregroundStyle(.secondary)
            Text("Mission Control").font(.system(.headline, design: .rounded, weight: .semibold))
            let waiting = room.calls.filter(\.awaitsYou)
            if !waiting.isEmpty {
                Label(waiting.count == 1 ? "\(waiting[0].agent.name) needs you" : "\(waiting.count) need you",
                      systemImage: "exclamationmark.bubble.fill")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(LairColors.attention)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(LairColors.attention.opacity(0.14), in: Capsule())
                    .onTapGesture { room.focus(waiting[0]) }
                    .help("Brings the first one into focus")
            }
            Spacer()
            if let shortcut = TalkKey.shared.label {
                Text("Hold \(shortcut) to talk · type below to write")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Divider() }
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

private struct StreamItem: Identifiable {
    enum Content {
        case entry(LogEntry)
        case details([String])
    }

    let id: UUID
    var content: Content
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
                        Text(call.guest ? "Nothing yet. \(call.agent.name) talks to you when it needs you."
                                        : "Nothing yet. Talk or type to \(call.agent.name).")
                            .font(.system(.callout, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 30)
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(stream) { item in
                        switch item.content {
                        case .entry(let entry): EntryView(entry: entry, tint: tint)
                        case .details(let facts): Details(facts: facts)
                        }
                    }
                }
                .padding(14)
            }
            .defaultScrollAnchor(.bottom)
            if let request = call.pendingApproval {
                ApprovalCard(agent: call.agent.name, request: request, tint: LairColors.attention, shortcuts: false) {
                    room.answer(call, decision: $0)
                }
                .padding([.horizontal, .top], 10)
            } else if let question = call.questionText {
                QuestionCard(agent: call.agent.name, question: question, choices: call.questionChoices, shortcuts: false,
                             since: call.questionSince,
                             deadline: call.questionDeadline, tint: LairColors.attention,
                             answer: { room.answerQuestion(of: call, with: $0) }, skip: { room.skipQuestion(of: call) })
                    .padding([.horizontal, .top], 10)
            }
            if !call.guest { composer(tint: tint) }
        }
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(focused ? tint.opacity(0.7) : .primary.opacity(0.1), lineWidth: focused ? 1.5 : 1))
        .shadow(color: focused ? tint.opacity(0.25) : .clear, radius: 18)
        .contentShape(Rectangle())
        .onTapGesture { room.focus(call) }
    }

    /// The approval line repeats the card while it asks, and the note of the answer says the rest afterwards.
    /// A turn's usage and timings fold into one Details row.
    private var stream: [StreamItem] {
        var items: [StreamItem] = []
        for entry in call.entries {
            if case .approval = entry.kind { continue }
            if let facts = EntryView.facts(of: entry) {
                if case .details(let before) = items.last?.content {
                    items[items.count - 1].content = .details(before + facts)
                } else {
                    items.append(StreamItem(id: entry.id, content: .details(facts)))
                }
            } else {
                items.append(StreamItem(id: entry.id, content: .entry(entry)))
            }
        }
        return items
    }

    private func header(tint: Color) -> some View {
        HStack(spacing: 12) {
            Orb(color: tint, state: call.state, meter: nil)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(call.agent.name).font(.system(.headline, design: .rounded, weight: .semibold))
                if call.guest {
                    GuestBadge(folder: call.folder)
                } else {
                    Text([call.details, stateText].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if call.questionText != nil {
                Label("Asks you", systemImage: "questionmark.bubble.fill")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(LairColors.attention)
            } else if call.state == .waiting {
                Label("Needs your OK", systemImage: "hand.raised.fill")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(LairColors.attention)
            }
            if call.guest {
                Button { room.toggle(call) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 28, height: 28)
                        .background(.primary.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Dismiss \(call.agent.name); it comes back when it next talks to you")
                .accessibilityLabel("Dismiss \(call.agent.name)")
            } else {
                Button { room.toggle(call) } label: {
                    Image(systemName: call.inCall ? "phone.down.fill" : "phone.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(call.inCall ? LairColors.hangUp : LairColors.call,
                                    in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(room.readiness != .ready)
                .help(call.inCall ? "Hang up" : "Call \(call.agent.name)")
                .accessibilityLabel(call.inCall ? "Hang up \(call.agent.name)" : "Call \(call.agent.name)")
            }
        }
        .padding(12)
    }

    private var stateText: String {
        call.state == .listening && room.answering?.callID == call.id ? "Listening for your reply" : call.state.label
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
                    .background(draft.isEmpty ? .primary.opacity(0.25) : tint, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityLabel("Send to \(call.agent.name)")
        }
        .padding(10)
        .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                .background(.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 40)
        case .agent(let text):
            Text(Self.reading(text))
                .textSelection(.enabled)
                .font(.system(.body))
                .fixedSize(horizontal: false, vertical: true)
        case .thinking(let text):
            ThinkingBlock(text: text)
        case .tool(let name, let input, let output, let failed):
            ToolCard(name: name, input: input, output: output, failed: failed, tint: tint)
        case .note(let text):
            Label(text, systemImage: "info.circle")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
        case .problem(let text):
            Label(text, systemImage: "exclamationmark.triangle.fill")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(LairColors.problem)
                .textSelection(.enabled)
        case .approval, .usage, .timing:
            EmptyView()
        }
    }

    /// The numbers behind a turn, when the entry is one of them.
    static func facts(of entry: LogEntry) -> [String]? {
        switch entry.kind {
        case .usage(let input, let output, let cost):
            return ["\(tokens(input)) in", "\(tokens(output)) out"] + (cost.map { [String(format: "$%.3f", $0)] } ?? [])
        case .timing(let heard, let firstWord, let firstSound, let total):
            return [heard.map { "heard \(time($0))" }, firstWord.map { "first word \(time($0))" },
                    firstSound.map { "first sound \(time($0))" }, "turn \(time(total))"].compactMap { $0 }
        default:
            return nil
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
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            Text(text)
                .font(.system(.callout, design: .serif).italic())
                .foregroundStyle(.secondary)
                .lineLimit(open ? nil : 2)
                .textSelection(.enabled)
        }
        .padding(.leading, 10)
        .overlay(alignment: .leading) { Rectangle().fill(.primary.opacity(0.15)).frame(width: 2) }
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
                        .foregroundStyle(.secondary)
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
                Divider()
                ScrollView {
                    Output(text: output)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 240)
            }
        }
        .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(failed ? LairColors.problem.opacity(0.5) : .primary.opacity(0.12)))
    }

    @ViewBuilder private var status: some View {
        if output == nil {
            ProgressView().controlSize(.mini)
        } else if failed {
            Image(systemName: "xmark.circle.fill").foregroundStyle(LairColors.problem)
        } else {
            Image(systemName: open ? "chevron.up" : "checkmark.circle.fill")
                .foregroundStyle(open ? .secondary : LairColors.call)
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
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return .adaptive(light: (0.05, 0.4, 0.15), dark: (0.55, 0.9, 0.6)) }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return .adaptive(light: (0.7, 0.1, 0.1), dark: (1, 0.55, 0.55)) }
        if line.hasPrefix("@@") { return .adaptive(light: (0.1, 0.3, 0.75), dark: (0.55, 0.7, 1)) }
        return .primary
    }

    private func background(for line: Substring) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return .green.opacity(0.08) }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return .red.opacity(0.08) }
        return .clear
    }
}

/// A turn's timings, tokens and cost, folded away until you open them.
private struct Details: View {
    let facts: [String]
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { withAnimation(.smooth(duration: 0.2)) { open.toggle() } } label: {
                HStack(spacing: 4) {
                    Text("Details").font(.system(.caption2, design: .rounded, weight: .semibold))
                    Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            if open {
                Text(facts.joined(separator: " · "))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

private extension Color {
    /// One color per appearance, for text that has to read on both.
    static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let c = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
}
