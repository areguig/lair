import LairCore
import SwiftUI

/// Settings › On this Mac: lets agents you run yourself talk to you through Lair, and connects them in one click.
struct GuestSettingsView: View {
    let store: ConfigStore
    let link: GuestLink
    @State private var environment: [String: String]?
    @State private var claude = Connection.checking
    @State private var omp = Connection.checking
    @State private var copied: String?
    @State private var token: String?

    enum Connection: Equatable {
        case checking, missing, off, on, working, failed(String)
    }

    private var settings: GuestSettings? { store.config.guests }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { settings != nil }, set: turn)) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Let agents on this Mac talk to me")
                        Text("Agents you run in a terminal or an editor speak to you and ask you things out loud.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if settings != nil { statusRow }
            } footer: {
                Text("Only this Mac can connect, and only agents connected here: each one gets Lair's token.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let settings {
                Section("Connect") {
                    ConnectRow(name: "Claude Code", detail: "Every Claude Code session, in any folder",
                               symbol: "terminal", tint: Color(hex: "#D97757"), state: claude) {
                        await toggleClaude(settings)
                    }
                    ConnectRow(name: "omp", detail: "Every omp session, in any folder",
                               symbol: "chevron.left.forwardslash.chevron.right", tint: Color(hex: "#7B5CFF"), state: omp) {
                        toggleOmp(settings)
                    }
                }
                Section {
                    LabeledContent("Address") {
                        copyable(settings.url.absoluteString, shown: settings.url.absoluteString)
                    }
                    LabeledContent("Header") {
                        copyable(token.map { "Authorization: Bearer \($0)" } ?? "", shown: "Authorization: Bearer ••••••••")
                    }
                } header: {
                    Text("Any other agent")
                } footer: {
                    Text("Add Lair to its MCP servers as a Streamable HTTP server named lair, with this header. "
                         + "Questions wait \(settings.answerSeconds) seconds for your answer: give the agent at least that long for a tool call.")
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .formStyle(.grouped)
        .task(id: settings) { await refresh() }
    }

    @ViewBuilder private var statusRow: some View {
        switch link.status {
        case .on(let url):
            Label {
                Text("Listening at ") + Text(url.absoluteString).font(.system(.body, design: .monospaced))
            } icon: {
                Circle().fill(.green).frame(width: 8, height: 8)
            }
            .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .off:
            EmptyView()
        }
    }

    private func copyable(_ value: String, shown: String) -> some View {
        HStack(spacing: 8) {
            Text(shown).font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
            Button(copied == value ? "Copied" : "Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
                copied = value
            }
            .controlSize(.small)
        }
    }

    private func turn(_ on: Bool) {
        var config = store.config
        config.guests = on ? (config.guests ?? .standard) : nil
        store.save(config)
    }

    private func refresh() async {
        if settings != nil, token == nil { token = try? GuestConnection.token() }
        if environment == nil { environment = await LoginShell.environment() }
        guard let environment else { return }
        let ompFile = GuestConnection.Omp.standard
        omp = await GuestConnection.isInstalled("omp", environment: environment) ? (ompFile.isConnected ? .on : .off) : .missing
        let cli = GuestConnection.ClaudeCode(environment: environment)
        claude = await GuestConnection.isInstalled("claude", environment: environment)
            ? (await cli.isConnected() ? .on : .off) : .missing
    }

    private func toggleClaude(_ settings: GuestSettings) async {
        guard let environment else { return }
        let cli = GuestConnection.ClaudeCode(environment: environment)
        let wasOn = claude == .on
        claude = .working
        do {
            if wasOn { try await cli.disconnect() } else { try await cli.connect(url: settings.url, token: GuestConnection.token()) }
            claude = wasOn ? .off : .on
        } catch {
            claude = .failed(error.localizedDescription)
        }
    }

    private func toggleOmp(_ settings: GuestSettings) {
        let file = GuestConnection.Omp.standard
        do {
            if omp == .on {
                try file.disconnect()
            } else {
                try file.connect(url: settings.url, token: GuestConnection.token(), answerSeconds: settings.answerSeconds)
            }
            omp = file.isConnected ? .on : .off
        } catch {
            omp = .failed(error.localizedDescription)
        }
    }
}

/// One agent you can connect: what it is, whether it's connected, and the one button that changes that.
private struct ConnectRow: View {
    let name: String
    let detail: String
    let symbol: String
    let tint: Color
    let state: GuestSettingsView.Connection
    let toggle: () async -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                Text(caption).font(.caption).foregroundStyle(captionColor).lineLimit(2)
            }
            Spacer()
            switch state {
            case .checking, .working:
                ProgressView().controlSize(.small)
            case .missing:
                Text("Not installed").font(.caption).foregroundStyle(.secondary)
            case .on:
                Button("Disconnect") { Task { await toggle() } }
            case .off, .failed:
                Button("Connect") { Task { await toggle() } }.buttonStyle(.borderedProminent).tint(tint)
            }
        }
        .padding(.vertical, 2)
    }

    private var caption: String {
        switch state {
        case .on: "Connected · new sessions can talk to you"
        case .failed(let message): message
        default: detail
        }
    }

    private var captionColor: Color {
        switch state {
        case .on: .green
        case .failed: .orange
        default: .secondary
        }
    }
}
