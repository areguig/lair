import LairCore
import SwiftUI

/// A problem with its way out, under the agent's name.
struct Problem<Actions: View>: View {
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
struct Banner: View {
    let text: String
    let action: String
    let perform: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(LairColors.problem)
            Text(text)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer(minLength: 4)
            Button(action, action: perform).buttonStyle(PillButtonStyle())
        }
        .padding(10)
        .background(LairColors.problem.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill").foregroundStyle(tint)
                Text("\(agent) needs your OK").font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(request.tool)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            // A long command stays readable without pushing the panel off screen; the whole text is in the tooltip.
            Text(request.summary)
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(5)
                .fixedSize(horizontal: false, vertical: true)
                .help(request.summary)
                .textSelection(.enabled)
            HStack(spacing: 8) {
                Button { answer(.deny) } label: {
                    Text("Deny").frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(Color.primary.opacity(0.1), in: Capsule())
                        .outlined(Capsule(), opacity: 0)
                }
                .keyboardShortcut(shortcuts ? .cancelAction : nil)
                if request.canAlwaysAllow {
                    Button { answer(.allowAlways) } label: {
                        Text("Always allow").fontWeight(.semibold)
                            .foregroundStyle(scheme == .light ? tint.mix(with: .black, by: 0.35) : tint).lineLimit(1)
                            .frame(maxWidth: .infinity).padding(.vertical, 7)
                            .background(tint.opacity(0.22), in: Capsule())
                    }
                }
                Button { answer(.allowOnce) } label: {
                    Text("Allow").fontWeight(.semibold).foregroundStyle(Color.inverse)
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(.primary, in: Capsule())
                }
                .keyboardShortcut(shortcuts ? .defaultAction : nil)
            }
            .buttonStyle(.plain)
            .font(.system(.callout, design: .rounded))
        }
        .padding(14)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .outlined(RoundedRectangle(cornerRadius: 16, style: .continuous), tint, opacity: 0.5)
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
                .foregroundStyle(.primary)
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
                        Text(placeholder).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .font(.system(.callout, design: .rounded))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color.primary.opacity(0.08), in: Capsule())
                Button(action: skip) {
                    Text("Skip").padding(.horizontal, 12).padding(.vertical, 7).background(Color.primary.opacity(0.1), in: Capsule())
                }
                .help("Tell \(agent) you won't answer; it carries on")
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.inverse)
                        .frame(width: 30, height: 30)
                        .background(Color.primary.opacity(draft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.3 : 1), in: Circle())
                }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Send your answer to \(agent)")
            }
            .buttonStyle(.plain)
            .font(.system(.callout, design: .rounded))
        }
        .padding(14)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .outlined(RoundedRectangle(cornerRadius: 16, style: .continuous), tint, opacity: 0.5)
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
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 6).padding(.trailing, 12).padding(.vertical, 6)
        .background(Color.primary.opacity(0.1), in: Capsule())
        .outlined(Capsule(), tint, opacity: 0.35)
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
                Capsule().fill(Color.primary.opacity(0.12))
                    .frame(width: 44, height: 4)
                    .overlay(alignment: .leading) {
                        Capsule().fill(tint).frame(width: 44 * left / total, height: 4)
                    }
                Text(Duration.seconds(left.rounded(.up)).formatted(.time(pattern: .minuteSecond)))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .motion(.linear(duration: 1), value: left)
        }
        .accessibilityLabel("Waits for your answer")
    }
}
