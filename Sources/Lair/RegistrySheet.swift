import LairCore
import SwiftUI

/// "More agents…": the ACP Registry's agents that Lair can start, to search and add.
struct RegistrySheet: View {
    let store: RegistryStore
    let room: Room
    /// Entry ids already added, which show "Added" instead of a button.
    let added: Set<String>
    let add: (Registry.Entry) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("More agents").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .top], 16)
            TextField("Search", text: $query, prompt: Text("Search agents"))
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search agents")
                .padding(16)
            Divider()
            if entries.isEmpty {
                Text(emptyMessage)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(entries) { entry in
                    RegistryRow(entry: entry, installed: room.isInstalled(program: entry.program),
                                isAdded: added.contains(entry.id)) { add(entry) }
                }
            }
        }
        .frame(width: 540, height: 480)
    }

    private var entries: [Registry.Entry] {
        let agents = store.registry?.agents ?? []
        let terms = query.split(separator: " ")
        return agents.filter { entry in
            terms.allSatisfy { entry.name.localizedCaseInsensitiveContains($0) || entry.description.localizedCaseInsensitiveContains($0) }
        }
    }

    private var emptyMessage: String {
        if store.registry == nil { return store.isLoading ? "Loading the list…" : "Couldn't load the list. Check your connection." }
        return "No agent matches “\(query)”."
    }
}

private struct RegistryRow: View {
    let entry: Registry.Entry
    /// Nil until the login shell's PATH is known.
    let installed: Bool?
    let isAdded: Bool
    let add: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // The registry's icons are SVGs that draw in the text color; a plain symbol keeps every row the same.
            Image(systemName: "terminal")
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name).font(.headline)
                Text(entry.description).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 8) {
                    Text(entry.license)
                    if let website = entry.website { Link("Website", destination: website) }
                    if installed == false {
                        Text("Needs \(entry.needs)")
                        Link("Get", destination: entry.installURL).accessibilityLabel("Get \(entry.needs)")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isAdded {
                Text("Added").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Button("Add", action: add)
                    .accessibilityLabel("Add \(entry.name)")
                    .accessibilityHint("Saves the agent with the exact command that starts it")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }
}
