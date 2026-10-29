import KeyboardShortcuts
import LairCore
import LairVoice
import ServiceManagement
import SwiftUI
import os

/// Agents and preferences. Every change is written to the config file as you make it.
struct SettingsView: View {
    static let id = "settings"
    static let title = "Lair Settings"

    /// A menu-bar app isn't the active app when its panel is clicked, so polite activation leaves the window
    /// behind others: raise it explicitly once it exists, then make it key.
    @MainActor static func bringForward() {
        NSApp.activate()
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: { $0.title == title }) else { return }
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
        }
    }
    let store: ConfigStore
    let room: Room
    /// The agent shown first; snapshots use it to show a given form.
    var selectedAgent: String?

    var body: some View {
        TabView {
            AgentsSettings(store: store, room: room, selection: selectedAgent)
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
    @State var selection: String?
    @State private var removing: AgentConfig?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(store.config.agents, selection: $selection) { agent in
                    HStack(spacing: 8) {
                        Circle().fill(Color(hex: agent.color)).frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(agent.name.isEmpty ? "Unnamed" : agent.name)
                            Text(agent.disabled == true ? "\(agent.kind.label) · off" : agent.kind.label)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .opacity(agent.disabled == true ? 0.5 : 1)
                        if hasProblem(agent) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                .help("This agent needs attention")
                                .accessibilityLabel("Needs attention")
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
                    .accessibilityLabel("Add an agent")
                    Button {
                        removing = store.config.agents.first { $0.id == selection }
                    } label: {
                        Image(systemName: "minus").frame(width: 24, height: 20)
                    }
                    .buttonStyle(.borderless)
                    .disabled(selection == nil)
                    .help("Remove the selected agent")
                    .accessibilityLabel("Remove the selected agent")
                    Spacer()
                }
                .padding(6)
                .background(Color(nsColor: .windowBackgroundColor))
            }
            .frame(width: 190)
            Divider()
            if let index = store.config.agents.firstIndex(where: { $0.id == selection }) {
                AgentForm(agent: binding(at: index), others: store.config.agents.filter { $0.id != selection }, room: room)
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

    private func hasProblem(_ agent: AgentConfig) -> Bool {
        let others = store.config.agents.filter { $0.id != agent.id }
        if nameProblem(agent.name, others: others) != nil { return true }
        guard agent.kind == .hermes else { return false }
        return addressProblem(agent.url) != nil || Keychain.password(service: agent.keychainService, account: "api-key") == nil
    }

    private func add(_ kind: AgentConfig.Kind) {
        var config = store.config
        let used = Set(config.agents.map(\.voice))
        // "Claude Code", then "Claude Code 2"…: two new agents never share a name.
        let taken = Set(config.agents.map { $0.name.lowercased() })
        var name = kind.label
        var n = 2
        while taken.contains(name.lowercased()) { name = "\(kind.label) \(n)"; n += 1 }
        let agent = AgentConfig(
            id: config.newAgentID(for: kind.label), name: name, kind: kind,
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
        for account in agent.secretAccounts { Keychain.delete(service: agent.keychainService, account: account) }
        Souls.standard.remove(agent.id)
        selection = config.agents.first?.id
    }
}

private struct AgentForm: View {
    @Binding var agent: AgentConfig
    let others: [AgentConfig]
    let room: Room

    var body: some View {
        Form {
            Section {
                Toggle("On", isOn: Binding(get: { agent.disabled != true }, set: { agent.disabled = $0 ? nil : true }))
                    .help("Off keeps this agent's settings but takes it out of the panel and Mission Control")
                VStack(alignment: .leading, spacing: 2) {
                    TextField("Name", text: $agent.name, prompt: Text("What you call it by voice"))
                    if let problem = nameProblem(agent.name, others: others) { Helper(problem) }
                }
                Picker("Kind", selection: kind) {
                    ForEach(AgentConfig.Kind.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                ColorPicker("Color", selection: Binding(get: { Color(hex: agent.color) }, set: { agent.color = $0.hex }),
                            supportsOpacity: false)
                HStack {
                    Picker("Voice", selection: $agent.voice) {
                        ForEach(VoiceModels.voices, id: \.self) { Text(voiceLabel($0)).tag($0) }
                    }
                    Button {
                        room.preview(voice: agent.voice, name: agent.name.isEmpty ? "your agent" : agent.name)
                    } label: {
                        Image(systemName: "play.fill")
                    }
                    .help("Hear this voice")
                    .accessibilityLabel("Hear this voice")
                    .disabled(room.readiness != .ready)
                }
            }
            Section {
                switch agent.kind {
                case .claudeCode:
                    ModelField(model: $agent.model, prompt: "Claude Code's default",
                               choices: [("Opus", "opus"), ("Sonnet", "sonnet"), ("Haiku", "haiku")], emptyHint: nil)
                    ThinkingPicker(title: "Effort", thinking: $agent.thinking, levels: ["low", "medium", "high", "xhigh", "max"])
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
                    let known = (room.knownModels[agent.id] ?? []).sorted()
                    ModelField(model: $agent.model, prompt: "omp's default", choices: known.map { ($0, $0) },
                               emptyHint: "Call this agent once to list its models")
                    ThinkingPicker(title: "Thinking", thinking: $agent.thinking,
                                   levels: ["off", "minimal", "low", "medium", "high", "xhigh", "max"])
                    FolderField(path: $agent.directory)
                case .hermes:
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("Address", text: optional($agent.url), prompt: Text("http://hermes.local:8642"))
                        if let problem = addressProblem(agent.url) { Helper(problem) }
                    }
                    TextField("Model", text: optional($agent.model), prompt: Text("hermes-agent"))
                    SecretField(title: "API key", service: agent.keychainService, account: "api-key")
                }
            } footer: {
                Text(footer)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if agent.kind == .hermes {
                ExtraHeaders(agent: $agent)
            } else {
                SoulEditor(agentID: agent.id)
            }
        }
        .formStyle(.grouped)
    }

    /// Switching kind drops the settings that only made sense for the old one.
    private var kind: Binding<AgentConfig.Kind> {
        Binding(get: { agent.kind }, set: { new in
            guard new != agent.kind else { return }
            agent.kind = new
            agent.model = nil
            agent.thinking = nil
            agent.directory = new == .hermes ? nil : "~"
            if new != .hermes { agent.url = nil; agent.headers = nil }
            if new != .claudeCode { agent.permissionMode = nil }
        })
    }

    private var footer: String {
        switch agent.kind {
        case .claudeCode: "These apply from the next call. During a call, say “switch to Opus” or “go fast”."
        case .omp: "These apply from the next call. During a call, say “think harder”, “go fast” or “switch to <model>”."
        case .hermes: "Address and model apply from the next call. Keys stay in your Keychain, never in the config file."
        }
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

/// Free-text model plus a menu of known choices; empty text means the agent's own default.
private struct ModelField: View {
    @Binding var model: String?
    let prompt: String
    let choices: [(label: String, value: String)]
    /// Shown, disabled, when there are no choices yet.
    let emptyHint: String?

    var body: some View {
        HStack(spacing: 4) {
            TextField("Model", text: Binding(get: { model ?? "" }, set: { model = $0.isEmpty ? nil : $0 }),
                      prompt: Text(prompt))
            Menu {
                Button("Default") { model = nil }
                Divider()
                ForEach(choices, id: \.value) { choice in
                    Button(choice.label) { model = choice.value }
                }
                if choices.isEmpty, let emptyHint { Button(emptyHint) {}.disabled(true) }
            } label: {
                Image(systemName: "chevron.down")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Choose a model")
        }
    }
}

private struct ThinkingPicker: View {
    let title: String
    @Binding var thinking: String?
    let levels: [String]

    var body: some View {
        Picker(title, selection: $thinking) {
            Text("Default").tag(String?.none)
            ForEach(levels, id: \.self) { Text($0).tag(String?($0)) }
        }
    }
}

private struct Helper: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.caption).foregroundStyle(.red) }
}

private func nameProblem(_ name: String, others: [AgentConfig]) -> String? {
    let name = name.trimmingCharacters(in: .whitespaces)
    if name.isEmpty { return "A name is needed to call this agent by voice" }
    if others.contains(where: { $0.name.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(name) == .orderedSame }) {
        return "Another agent already has this name; saying it would be ambiguous"
    }
    return nil
}

private func addressProblem(_ address: String?) -> String? {
    guard let address, !address.isEmpty else { return "Needed to reach the agent" }
    guard let url = URL(string: address), ["http", "https"].contains(url.scheme?.lowercased()), url.host?.isEmpty == false
    else { return "Use a full address, like http://hermes.local:8642" }
    return nil
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

/// This agent's own soul: its personality on calls, kept in `souls/<id>.md` and saved as you type.
private struct SoulEditor: View {
    let agentID: String
    @State private var text = ""
    @State private var loaded = false

    var body: some View {
        Section {
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 110)
                .scrollContentBackground(.hidden)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("How this agent talks and behaves on a call: tone, humor, how much it says, how it calls you…")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 1)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
                .onChange(of: text) { if loaded { try? Souls.standard.save(text, for: agentID) } }
        } header: {
            HStack {
                Text("Soul")
                Spacer()
                Menu("Start from…") {
                    ForEach(Souls.starters, id: \.name) { starter in
                        Button(starter.name) { text = starter.text }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        } footer: {
            Text("Only this agent gets it, from its next call. It's a Markdown file you can also edit by hand.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            text = Souls.standard.soul(for: agentID) ?? ""
            loaded = true
        }
    }
}

/// Headers a proxy in front of the agent may need (an access token, for example): names in the config file,
/// values in the Keychain.
private struct ExtraHeaders: View {
    @Binding var agent: AgentConfig
    @State private var newName = ""

    var body: some View {
        Section {
            ForEach(agent.headers ?? [], id: \.self) { name in
                HStack {
                    SecretField(title: name, service: agent.keychainService, account: AgentConfig.headerAccount(name))
                    Button {
                        Keychain.delete(service: agent.keychainService, account: AgentConfig.headerAccount(name))
                        agent.headers = (agent.headers ?? []).filter { $0 != name }.nilIfEmpty
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove this header")
                    .accessibilityLabel("Remove header \(name)")
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    TextField("Add a header", text: $newName, prompt: Text("Header name, like X-Access-Token"))
                        .onSubmit(add)
                    Button("Add", action: add).disabled(!isValid(newName))
                }
                if let hint = headerHint(newName) { Helper(hint) }
            }
        } header: {
            Text("Extra headers")
        } footer: {
            Text("Only needed when a proxy in front of the agent wants its own token. Values are kept in your Keychain.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard isValid(name) else { return }
        agent.headers = (agent.headers ?? []) + [name]
        newName = ""
    }

    /// HTTP header names: letters, digits and hyphens, not already listed.
    private func isValid(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && headerHint(name) == nil
    }

    /// Why the typed name can't be added; nil while empty or fine.
    private func headerHint(_ name: String) -> String? {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        if !name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) { return "Letters, digits and hyphens only" }
        if (agent.headers ?? []).contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) { return "Already added" }
        return nil
    }
}

private extension Array {
    var nilIfEmpty: Self? { isEmpty ? nil : self }
}

/// A secret kept in the Keychain: shows whether one is saved, never what it is.
private struct SecretField: View {
    let title: String
    let service: String
    let account: String
    @State private var value = ""
    @State private var saved = false
    @State private var replacing = false
    @State private var problem: String?

    var body: some View {
        LabeledContent(title) {
            HStack {
                if saved && !replacing {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Button("Replace") { replacing = true }
                    Button("Remove") {
                        Keychain.delete(service: service, account: account)
                        saved = false
                    }
                } else {
                    SecureField(title, text: $value, prompt: Text("Paste the value"))
                        .labelsHidden()
                        .frame(minWidth: 180)
                        .onSubmit(save)
                    Button("Save", action: save).disabled(value.isEmpty)
                    if replacing { Button("Cancel") { replacing = false; value = "" } }
                }
            }
        }
        .onAppear { saved = Keychain.password(service: service, account: account) != nil }
        .help(problem ?? "")
    }

    private func save() {
        guard !value.isEmpty else { return }
        do {
            try Keychain.setPassword(value, service: service, account: account)
            saved = true
            replacing = false
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
                Toggle("Listen for my reply after the agent speaks", isOn: Binding(
                    get: { store.config.listensForAnswers },
                    set: { on in
                        var config = store.config
                        config.listenForAnswers = on ? nil : false
                        store.save(config)
                    }))
                Toggle("Open at login", isOn: Binding(get: { opensAtLogin }, set: { setOpensAtLogin($0) }))
            } footer: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pick a shortcut no other app uses; it works from anywhere.")
                    Text("The mic opens for a few seconds once the agent stops talking, and sends when you stop.")
                    Text("Allow notifications to answer approvals from anywhere; without them, answer by voice or in the panel.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
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
            Section {
                Text(Self.version).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        guard let short = info?["CFBundleShortVersionString"] as? String else { return "Lair, development build" }
        return "Lair \(short)" + ((info?["CFBundleVersion"] as? String).map { " (build \($0))" } ?? "")
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
