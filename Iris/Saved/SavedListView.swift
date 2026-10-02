import SwiftData
import SwiftUI

struct SavedListView: View {
    let open: (SavedSite) -> Void
    let openOffline: (SavedSite) -> Void
    let openHistory: (URL) -> Void
    @Environment(SettingsStore.self) private var settings
    @Query(sort: \SavedSite.createdAt, order: .reverse) private var sites: [SavedSite]
    @State private var search = ""
    @State private var renaming: SavedSite?
    @State private var newTitle = ""
    @State private var error: String?
    @State private var deleting: SavedSite?
    @State private var showingHistory = false
    private var filtered: [SavedSite] {
        sites.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.url.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Saved or History", selection: $showingHistory) {
                    Text("Saved").tag(false)
                    Text("History").tag(true)
                }.pickerStyle(.segmented).padding()
                if showingHistory { HistoryListView(open: openHistory) }
                else { savedList }
            }
            .navigationTitle(showingHistory ? "History" : "Saved Sites")
        }.frame(width: 460, height: 540)
    }

    private var savedList: some View {
            List {
                if filtered.isEmpty { Text(search.isEmpty ? "No saved sites yet" : "No matching sites").foregroundStyle(.secondary) }
                ForEach(filtered) { site in
                    Button { open(site) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(site.title).lineLimit(1)
                            Text(site.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            if site.archiveFileName != nil { Label("Offline copy saved", systemImage: "arrow.down.doc").font(.caption2) }
                        }
                    }.hoverEffect()
                        .contextMenu {
                            Button("Rename", systemImage: "pencil") { newTitle = site.title; renaming = site }
                            if site.archiveFileName != nil {
                                Button("Open offline copy", systemImage: "doc") { openOffline(site) }
                            }
                            Button("Delete", systemImage: "trash", role: .destructive) { deleting = site }
                        }
                }
            }
            .searchable(text: $search, prompt: "Search saved sites")
            .alert("Rename site", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Title", text: $newTitle)
                Button("Save") {
                    if let site = renaming, !newTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                        site.title = newTitle.trimmingCharacters(in: .whitespaces)
                        settings.save()
                        error = settings.persistenceError
                    }
                    renaming = nil
                }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
            .confirmationDialog("Delete saved site?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                presenting: deleting) { site in
                Button("Delete", role: .destructive) { Task { error = await settings.removeSaved(site) } }
            } message: { site in
                Text(site.archiveFileName == nil ? site.title : "\(site.title) and its offline copy will be deleted.")
            }
            .alert("Unable to update saved site", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
    }
}
