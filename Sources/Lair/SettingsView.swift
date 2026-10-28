import KeyboardShortcuts
import LairCore
import LairVoice
import ServiceManagement
import SwiftUI
import os

/// Agents and preferences. Every change is written to the config file as you make it.
struct SettingsView: View {
    static let id = "settings"
    let store: ConfigStore
    let room: Room

    var body: some View {
        TabView {
            AgentsSettings(store: store, room: room)
                .tabItem { Label("Agents", systemImage: "person.2") }
            GeneralSettings(store: store)
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 660, height: 500)
    }
}

// MARK: - Agents

private struct AgentsSettings: View {
    let store: ConfigStore
    let room: Room
    @State private var selection: String?
    @State private var removing: AgentConfig?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(store.config.agents, selection: $selection) { agent in
                    HStack(spacing: 8) {
                        Circle().fill(Color(hex: agent.color)).frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(agent.name.isEmpty ? "Unnamed" : agent.name)
                            Text(agent.kind.label).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .tag(agent.id)
                }
                .listStyle(.sidebar)
                HStack(spacing: 0) {
                    Menu {
                        ForEach(AgentConfig.Kind.allCases, id: \.self) { kind in
                            Button(kind.label) { add(kind) }
                        }
                    } label: {
                        Image(systemName: "plus").frame(width: 24, height: 20)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Add an agent")
                    Button {
                        removing = store.config.agents.first { $0.id == selection }
                    } label: {
                        Image(systemName: "minus").frame(width: 24, height: 20)
                    }
                    .buttonStyle(.borderless)
                    .disabled(selection == nil)
                    .help("Remove the selected agent")
                    Spacer()
                }
                .padding(6)
            }
            .frame(width: 190)
            Divider()
            if let index = store.config.agents.firstIndex(where: { $0.id == selection }) {
                AgentForm(agent: binding(at: index), room: room)
                    .id(store.config.agents[index].id)
            } else {
                Text("Select an agent, or add one with +.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { selection = selection ?? store.config.agents.first?.id }
        .confirmationDialog("Remove \(removing?.name ?? "this agent")?", isPresented: Binding(
            get: { removing != nil }, set: { if !$0 { removing = nil } }
        )) {
            Button("Remove", role: .destructive) { if let removing { remove(removing) } }
        } message: {
            Text("Its call ends, and any keys Lair saved for it are removed from the Keychain.")
        }
    }

    private func binding(at index: Int) -> Binding<AgentConfig> {
        Binding(
            get: { store.config.agents[index] },
            set: { agent in
                var config = store.config
                guard config.agents.indices.contains(index) else { return }
                config.agents[index] = agent
                store.save(config)
            })
    }

    private func add(_ kind: AgentConfig.Kind) {
        var config = store.config
        let used = Set(config.agents.map(\.voice))
        let agent = AgentConfig(
            id: config.newAgentID(for: kind.label), name: kind.label, kind: kind,
            voice: VoiceModels.voices.first { !used.contains($0) } ?? "af_heart",
            color: AgentConfig.palette[config.agents.count % AgentConfig.palette.count],
            directory: kind == .hermes ? nil : "~")
        config.agents.append(agent)
        store.save(config)
        selection = agent.id
    }

    private func remove(_ agent: AgentConfig) {
        var config = store.config
        config.agents.removeAll { $0.id == agent.id }
        store.save(config)
        for account in AgentConfig.secretAccounts { Keychain.delete(service: agent.keychainService, account: account) }
        selection = config.agents.first?.id
    }
}

private struct AgentForm: View {
    @Binding var agent: AgentConfig
    let room: Room

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $agent.name, prompt: Text("What you call it by voice"))
                Picker("Kind", selection: $agent.kind) {
                    ForEach(AgentConfig.Kind.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                ColorPicker("Color", selection: Binding(get: { Color(hex: agent.color) }, set: { agent.color = $0.hex }),
                            supportsOpacity: false)
                HStack {
                    Picker("Voice", selection: $agent.voice) {
                        ForEach(VoiceModels.voices, id: \.self) { Text(voiceLabel($0)).tag($0) }
                    }
                    Button {
                        room.preview(voice: agent.voice, name: agent.name)
                    } label: {
                        Image(systemName: "play.fill")
                    }
                    .help("Hear this voice")
                    .disabled(room.readiness != .ready)
                }
            }
            Section {
                switch agent.kind {
                case .claudeCode:
                    TextField("Model", text: optional($agent.model), prompt: Text("Claude Code's default"))
                    FolderField(path: $agent.directory)
                    Picker("Approvals", selection: $agent.permissionMode) {
                        Text("As in my Claude Code settings").tag(String?.none)
                        Text("Ask before anything").tag(String?("manual"))
                        Text("Allow file edits").tag(String?("acceptEdits"))
                        Text("Plan only, change nothing").tag(String?("plan"))
                        Text("Let Claude decide").tag(String?("auto"))
                        Text("Allow everything").tag(String?("bypassPermissions"))
                    }
                case .omp:
                    TextField("Model", text: optional($agent.model), prompt: Text("omp's default"))
                    FolderField(path: $agent.directory)
                case .hermes:
                    TextField("Address", text: optional($agent.url), prompt: Text("http://hermes.local:8642"))
                    TextField("Model", text: optional($agent.model), prompt: Text("hermes-agent"))
                    SecretField(title: "API key", service: agent.keychainService, account: "api-key")
                    DisclosureGroup("Cloudflare Access") {
                        SecretField(title: "Client ID", service: agent.keychainService, account: "cf-access-client-id")
                        SecretField(title: "Client secret", service: agent.keychainService,
                                    account: "cf-access-client-secret")
                    }
                }
            } footer: {
                Text("Model, folder and address apply from the agent's next call. Keys stay in your Keychain, "
                     + "never in the config file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// An empty field means "not set", so the agent's own default applies.
    private func optional(_ value: Binding<String?>) -> Binding<String> {
        Binding(get: { value.wrappedValue ?? "" }, set: { value.wrappedValue = $0.isEmpty ? nil : $0 })
    }

    /// "bf_emma" → "Emma · British female".
    private func voiceLabel(_ voice: String) -> String {
        let parts = voice.split(separator: "_", maxSplits: 1)
        guard parts.count == 2, parts[0].count == 2 else { return voice }
        let accent = parts[0].first == "b" ? "British" : "American"
        let gender = parts[0].last == "m" ? "male" : "female"
        return "\(parts[1].capitalized) · \(accent) \(gender)"
    }
}

private struct FolderField: View {
    @Binding var path: String?

    var body: some View {
        LabeledContent("Folder") {
            HStack {
                Text(path ?? "Not set").foregroundStyle(path == nil ? .secondary : .primary)
                    .lineLimit(1).truncationMode(.middle)
                Button("Choose…", action: choose)
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = path.map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        path = url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }
}

/// A secret kept in the Keychain: shows whether one is saved, never what it is.
private struct SecretField: View {
    let title: String
    let service: String
    let account: String
    @State private var value = ""
    @State private var saved = false
    @State private var problem: String?

    var body: some View {
        LabeledContent(title) {
            HStack {
                SecureField(saved ? "Saved in Keychain" : "Not set", text: $value)
                    .onSubmit(save)
                Button("Save", action: save).disabled(value.isEmpty)
                if saved {
                    Button("Remove") {
                        Keychain.delete(service: service, account: account)
                        saved = false
                    }
                }
            }
        }
        .onAppear { saved = Keychain.password(service: service, account: account) != nil }
        .help(problem ?? "")
    }

    private func save() {
        do {
            try Keychain.setPassword(value, service: service, account: account)
            saved = true
            value = ""
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
    }
}

// MARK: - General

private struct GeneralSettings: View {
    let store: ConfigStore
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "lair", category: "login")

    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Hold to talk:", name: .pushToTalk)
                Toggle("Open at login", isOn: Binding(get: { opensAtLogin }, set: setOpensAtLogin))
            }
            Section {
                LabeledContent("Config file") {
                    Text(LairConfig.defaultURL.path.replacingOccurrences(
                        of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                        .textSelection(.enabled)
                }
                HStack {
                    Button("Open in Editor") { NSWorkspace.shared.open(LairConfig.defaultURL) }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([LairConfig.defaultURL]) }
                }
                if let problem = store.problem {
                    Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            } footer: {
                Text("This window and the file stay in sync: edits made in the file show up here within seconds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func setOpensAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            Self.log.error("login item: \(error.localizedDescription, privacy: .public)")
        }
        opensAtLogin = SMAppService.mainApp.status == .enabled
    }
}

// MARK: - Helpers

extension AgentConfig.Kind: CaseIterable {
    public static let allCases: [AgentConfig.Kind] = [.claudeCode, .omp, .hermes]

    var label: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .omp: "omp"
        case .hermes: "Hermes"
        }
    }
}

extension AgentConfig {
    static let palette = ["#D97757", "#7B5CFF", "#3FB68B", "#E5B93C", "#4BA3E3", "#E35D8F"]
    static let secretAccounts = ["api-key", "cf-access-client-id", "cf-access-client-secret"]
}

extension Color {
    /// `#RRGGBB` in sRGB, the format the config file uses.
    var hex: String {
        guard let rgb = NSColor(self).usingColorSpace(.sRGB) else { return "#808080" }
        let value = { (component: CGFloat) in Int((component * 255).rounded()).clamped(to: 0...255) }
        return String(format: "#%02X%02X%02X", value(rgb.redComponent), value(rgb.greenComponent), value(rgb.blueComponent))
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
