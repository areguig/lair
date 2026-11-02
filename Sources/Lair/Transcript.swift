import LairCore
import SwiftUI

/// What was said in this call: the newest line stays in view unless you scrolled up to read.
struct Transcript: View {
    let lines: [Call.Line]
    /// The agent's color, for the bar beside its words.
    let tint: Color
    /// Shown in turn while there are no words yet.
    let tips: [String]
    let perform: (Call.Line.Action) -> Void
    @Environment(\.renderTime) private var renderTime
    @State private var position = ScrollPosition(edge: .bottom)
    /// False once you scroll up; true again when you reach the bottom.
    @State private var following = true

    var body: some View {
        Group {
            if lines.isEmpty {
                TimelineView(.periodic(from: .now, by: 6)) { timeline in
                    let tick = Int(renderTime ?? timeline.date.timeIntervalSinceReferenceDate) / 6
                    Text(tips.isEmpty ? "" : tips[tick % tips.count])
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .contentTransition(.opacity)
                        .motion(.easeInOut(duration: 0.4), value: tick)
                }
            } else if renderTime == nil {
                ScrollView(showsIndicators: false) {
                    column(lines)
                }
                .defaultScrollAnchor(.bottom)
                .scrollPosition($position)
                .onScrollPhaseChange { _, phase, context in
                    guard phase == .idle else { return }
                    let geometry = context.geometry
                    following = geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 24
                }
                .onChange(of: lines.last?.text) { if following { position.scrollTo(edge: .bottom) } }
                .onChange(of: lines.count) { if following { position.scrollTo(edge: .bottom) } }
                .environment(\.openURL, OpenURLAction(handler: ShownText.open))
            } else {
                // Scroll views don't render offscreen: the newest lines, bottom-aligned, instead.
                column(Array(lines.suffix(6)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Older lines scroll away under a clean edge, not a fade.
        .clipped()
    }

    private func column(_ lines: [Call.Line]) -> some View {
        VStack(spacing: 12) {
            ForEach(lines) { row($0) }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func row(_ line: Call.Line) -> some View {
        switch line.role {
        case .you:
            Text(line.text)
                .textSelection(.enabled)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .outlined(RoundedRectangle(cornerRadius: 16, style: .continuous), opacity: 0)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 56)
        case .agent:
            HStack(alignment: .top, spacing: 10) {
                Capsule().fill(tint.opacity(0.85)).frame(width: 3)
                Text(line.text.isEmpty && line.shown.isEmpty ? AttributedString("…") : ShownText.attributed(line))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.trailing, 16)
        case .info:
            Text(line.text)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
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
            .frame(maxWidth: .infinity, alignment: .leading)
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
