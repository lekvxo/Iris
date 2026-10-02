import SwiftData
import WebKit

extension BrowserModel {
    func openArchive(_ site: SavedSite, settings: SettingsStore) async {
        // The next task wires the archive load to the navigation guard.
    }

    func saveOffline(existing: SavedSite?, settings: SettingsStore) async {
        guard !isSavingOffline, let view = webView, let url = view.url else { return }
        isSavingOffline = true
        saveError = nil
        defer { isSavingOffline = false }
        let site = existing ?? SavedSite(url: url, title: title)
        do {
            let data = try await view.createWebArchiveData()
            guard webView === view, view.url == url else { throw SavedError.pageChanged }
            let name = try await settings.archives.write(data, id: site.id)
            if existing == nil { settings.container.mainContext.insert(site) }
            site.archiveFileName = name
            settings.save()
            saveError = settings.persistenceError
        } catch { saveError = error.localizedDescription }
    }
}

enum SavedError: LocalizedError {
    case pageChanged
    var errorDescription: String? { "The page changed while saving. Please try again." }
}
