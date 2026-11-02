import LairCore
import SwiftUI

/// What was said in this call, newest at the bottom, fading out at the top.
struct Transcript: View {
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
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .contentTransition(.opacity)
                        .motion(.easeInOut(duration: 0.4), value: tick)
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
        .motion(.smooth, value: lines.isEmpty)
        .motion(.smooth, value: live)
    }

    @ViewBuilder private func row(_ line: Call.Line) -> some View {
        switch line.role {
        case .you:
            Text(line.text)
                .textSelection(.enabled)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .outlined(RoundedRectangle(cornerRadius: 14, style: .continuous), opacity: 0)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 40)
        case .agent:
            VStack(alignment: .leading, spacing: 6) {
                if !line.text.isEmpty || line.shown.isEmpty {
                    Text(line.text.isEmpty ? "…" : line.text)
                        .textSelection(.enabled)
                        .foregroundStyle(.primary)
                }
                ForEach(Array(line.shown.enumerated()), id: \.offset) { _, item in
                    ShownChip(item: item)
                }
            }
            .padding(.trailing, 24)
        case .info:
            Label(line.text, systemImage: "info.circle")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
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
            .foregroundStyle(.primary)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Color.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .outlined(RoundedRectangle(cornerRadius: 8, style: .continuous), opacity: 0)
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
