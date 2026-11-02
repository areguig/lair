import AppKit
import LairCore
import LairVoice
import ServiceManagement
import SwiftUI

/// Settings › General › "Reset or uninstall": shows what would go, asks, then removes it.
struct ResetSection: View {
    let store: ConfigStore
    @State private var asking: (scope: Cleanup.Scope, cleanup: Cleanup, plan: Cleanup.Plan)?
    @State private var problems: [String] = []
    @State private var isWorking = false

    var body: some View {
        Section {
            HStack {
                Button("Reset Lair…") { ask(.reset) }
                    .accessibilityHint("Brings Lair back to its first launch")
                Button("Uninstall Lair…") { ask(.uninstall) }
                    .accessibilityHint("Removes Lair, its speech models and the app")
            }
            .disabled(isWorking)
        } header: {
            Text("Reset or uninstall")
        } footer: {
            Text("Reset brings Lair back to its first launch. Uninstall also removes its speech models and the app. Everything goes to the Trash.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .confirmationDialog(asking?.scope == .uninstall ? "Uninstall Lair?" : "Reset Lair?",
                            isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } }),
                            titleVisibility: .visible, presenting: asking) { pending in
            Button(pending.scope == .uninstall ? "Uninstall Lair" : "Reset Lair", role: .destructive) { run(pending) }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text(Self.message(pending.scope, pending.plan))
        }
        .alert("Lair couldn't remove everything", isPresented: Binding(get: { !problems.isEmpty }, set: { if !$0 { problems = [] } })) {
            Button("OK") {}
        } message: {
            Text(problems.joined(separator: "\n"))
        }
    }

    /// What goes, one line each; files go to the Trash, but secrets and connections are removed for good.
    private static func message(_ scope: Cleanup.Scope, _ plan: Cleanup.Plan) -> String {
        var lines = plan.items.isEmpty ? ["Nothing of Lair is left to remove."] : plan.items.map { "• \($0.line)" }
        lines += plan.notes
        lines.append(scope == .uninstall
            ? "Files and the app go to the Trash. Saved secrets and connections are removed for good, then Lair quits."
            : "Files go to the Trash. Saved secrets and connections are removed for good, then Lair opens again as new.")
        return lines.joined(separator: "\n")
    }

    private func ask(_ scope: Cleanup.Scope) {
        isWorking = true
        Task {
            let cleanup = await Cleanup.forThisApp()
            asking = (scope, cleanup, await cleanup.plan(scope))
            isWorking = false
        }
    }

    private func run(_ pending: (scope: Cleanup.Scope, cleanup: Cleanup, plan: Cleanup.Plan)) {
        isWorking = true
        // The config is about to go; without this it would be written back as a new one.
        store.stopWatching()
        Task {
            let failures = await pending.cleanup.run(pending.plan)
            guard failures.isEmpty else {
                problems = failures.map { "\($0.label): \($0.message)" }
                store.watch()
                isWorking = false
                return
            }
            if pending.scope == .uninstall {
                // Not a normal quit: that would write the preferences just removed.
                exit(0)
            }
            relaunch()
        }
    }

    /// Opens a fresh Lair, which finds no config and shows the Welcome window, then closes this one.
    private func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if let error {
                    problems = ["Lair was reset but couldn't open again: \(error.localizedDescription)"]
                    store.watch()
                    isWorking = false
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }
}

extension Cleanup {
    /// Reset and Uninstall for this Mac: the real places, Lair's speech models, its connections and its login item.
    @MainActor static func forThisApp() async -> Cleanup {
        let environment = await LoginShell.environment()
        let claude = GuestConnection.ClaudeCode(environment: environment)
        let omp = GuestConnection.Omp.standard
        var appItems: [Item] = []
        if SMAppService.mainApp.status == .enabled {
            appItems.append(Item(label: "Open at login", remove: { try await SMAppService.mainApp.unregister() }))
        }
        if let domain = Bundle.main.bundleIdentifier {
            appItems.append(Item(label: "Preferences", remove: { UserDefaults.standard.removePersistentDomain(forName: domain) }))
        }
        // A bare executable (swift run) has no app to remove; its folder must never be taken for one.
        let app = Bundle.main.bundleURL.pathExtension == "app" ? Bundle.main.bundleURL : nil
        return Cleanup(
            places: .standard(speechModels: VoiceModels.folders, app: app),
            connections: [
                Connection(label: "Claude Code", isConnected: { await claude.isConnected() }, disconnect: { try await claude.disconnect() }),
                Connection(label: "omp", isConnected: { omp.isConnected }, disconnect: { try omp.disconnect() }),
            ],
            appItems: appItems)
    }
}
