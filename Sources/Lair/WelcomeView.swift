import LairCore
import LairVoice
import SwiftUI

/// The first launch: what Lair needs before you can talk, each with where it stands, on one page.
struct WelcomeView: View {
    static let id = "welcome"
    static let title = "Welcome to Lair"

    let store: ConfigStore
    let room: Room
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    private static let microphoneSettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!

    var body: some View {
        VStack(spacing: 20) {
            header
            VStack(spacing: 0) {
                voicesRow
                Divider()
                microphoneRow
                Divider()
                agentsRow
            }
            .padding(.horizontal, 16)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .outlined(RoundedRectangle(cornerRadius: 12, style: .continuous), opacity: 0.1)
            footer
        }
        .padding(24)
        .frame(width: 480)
    }

    private var header: some View {
        VStack(spacing: 6) {
            Orb(color: Color(hex: AgentConfig.palette[0]), state: .ready)
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            Text(Self.title).font(.largeTitle.bold())
            Text("Talk to your coding agents out loud. Three things to get ready.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Rows

    private var voicesRow: some View {
        WelcomeRow(title: "Voices", detail: voicesDetail, status: voicesStatus) {
            switch room.readiness {
            case .loading:
                if case .recognition(let fraction) = room.voiceProgress {
                    ProgressView(value: fraction).motion(.easeOut(duration: 0.3), value: fraction)
                }
            case .failed:
                Button("Try again") { Task { await room.prepare() } }
            case .ready, .microphoneDenied:
                EmptyView()
            }
        }
    }

    private var voicesStatus: WelcomeStatus {
        switch room.readiness {
        case .loading: .working
        case .ready: .done
        case .microphoneDenied: .waiting
        case .failed: .problem
        }
    }

    private var voicesDetail: String {
        switch room.readiness {
        case .loading:
            switch room.voiceProgress {
            case .recognition(let fraction): "Downloading speech recognition · \(Int(fraction * 100))%"
            case .voices: "Preparing the voices…"
            case nil: "Getting ready…"
            }
        case .ready: "Ready. They run on this Mac, so nothing you say leaves it."
        case .microphoneDenied: "Waiting for the microphone."
        case .failed(let message): message
        }
    }

    private var microphoneRow: some View {
        WelcomeRow(title: "Microphone", detail: microphoneDetail, status: microphoneStatus) {
            if room.readiness == .microphoneDenied {
                HStack {
                    Button("Open System Settings") { NSWorkspace.shared.open(Self.microphoneSettings) }
                    Button("Try again") { Task { await room.prepare() } }
                }
            }
        }
    }

    /// Voices only start loading once the microphone is allowed, so loading them is the proof.
    private var microphoneAllowed: Bool {
        switch room.readiness {
        case .ready, .failed: true
        case .loading: room.voiceProgress != nil
        case .microphoneDenied: false
        }
    }

    private var microphoneStatus: WelcomeStatus {
        if microphoneAllowed { return .done }
        return room.readiness == .microphoneDenied ? .problem : .attention
    }

    private var microphoneDetail: String {
        if microphoneAllowed { return "Allowed." }
        return room.readiness == .microphoneDenied
            ? "Lair can't hear you. Allow it in System Settings."
            : "Lair asks to use the microphone. Choose Allow."
    }

    private var agentsRow: some View {
        WelcomeRow(title: "Agents", detail: "Turn on the ones you want to talk to.", status: agentsStatus) {
            VStack(spacing: 0) {
                ForEach(AgentPreset.all) { preset in
                    AgentLine(preset: preset, installed: room.isInstalled(preset), isOn: binding(for: preset))
                    if preset != AgentPreset.all.last { Divider() }
                }
            }
            Button("More agents in Settings…") { openSettings() }
                .buttonStyle(.link)
                .padding(.top, 2)
        }
    }

    private var agentsStatus: WelcomeStatus {
        store.config.enabledAgents.isEmpty ? .attention : .done
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Text(readyMessage ?? "")
                .font(.headline)
                .accessibilityHidden(readyMessage == nil)
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
        }
    }

    /// Set once there is someone to talk to, a voice to hear them with and a microphone.
    private var readyMessage: String? {
        guard room.readiness == .ready, let agent = store.config.enabledAgents.first else { return nil }
        return "Hold \(TalkKey.shared.label ?? "the talk key") and say hi to \(agent.name)"
    }

    // MARK: Actions

    private func binding(for preset: AgentPreset) -> Binding<Bool> {
        Binding(
            get: { store.config.enabledAgents.contains { $0.preset == preset.id } },
            set: { setUsing(preset, $0) })
    }

    /// On adds an agent the way Settings does; off removes the ones made from this preset.
    private func setUsing(_ preset: AgentPreset, _ on: Bool) {
        var config = store.config
        if on {
            var agent = config.newAgent(named: preset.name, voices: VoiceModels.voices)
            AgentChoice.preset(preset.id).apply(to: &agent)
            config.agents.append(agent)
        } else {
            config.agents.removeAll { $0.preset == preset.id }
        }
        store.save(config)
    }

    private func openSettings() {
        SettingsRoute.shared.tab = .agents
        openWindow(id: SettingsView.id)
        SettingsView.bringForward()
    }
}

/// Where a step stands: done, busy, waiting for you, broken, or waiting for something else.
private enum WelcomeStatus { case done, working, attention, problem, waiting }

/// A step: its state on the left, what it is and where it stands beside it, and what you can do about it below.
private struct WelcomeRow<Content: View>: View {
    let title: String
    let detail: String
    let status: WelcomeStatus
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            indicator.frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(status == .problem ? LairColors.problem : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 14)
    }

    @ViewBuilder private var indicator: some View {
        switch status {
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title2)
                .accessibilityLabel("Done")
        case .working:
            ProgressView().controlSize(.small).accessibilityLabel("Working")
        case .attention:
            Image(systemName: "circle.dotted").foregroundStyle(LairColors.attention).font(.title2)
                .accessibilityLabel("Needs you")
        case .problem:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(LairColors.problem).font(.title3)
                .accessibilityLabel("Problem")
        case .waiting:
            Image(systemName: "circle.dotted").foregroundStyle(.secondary).font(.title2)
                .accessibilityLabel("Waiting")
        }
    }
}

/// One preset: a switch when it's on this Mac, else what to install.
private struct AgentLine: View {
    let preset: AgentPreset
    /// Nil until the login shell's PATH is known.
    let installed: Bool?
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(preset.name)
            Spacer(minLength: 8)
            switch installed {
            case true?:
                Toggle("Use \(preset.name)", isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
            case false?:
                Text("Needs \(preset.needs)").font(.subheadline).foregroundStyle(.secondary)
                Link("Get", destination: preset.installURL)
                    .font(.subheadline)
                    .accessibilityLabel("Get \(preset.needs)")
            case nil:
                ProgressView().controlSize(.small).accessibilityLabel("Looking for \(preset.name)")
            }
        }
        .padding(.vertical, 6)
        .frame(minHeight: 28)
    }
}
