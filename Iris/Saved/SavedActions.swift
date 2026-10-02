import SwiftData
import WebKit

extension BrowserModel {
    func openArchive(_ site: SavedSite, settings: SettingsStore) async {
        guard let name = site.archiveFileName, let url = URL(string: site.url), let view = webView else { return }
        do {
            let data = try await settings.archives.read(name)
            guard webView === view else { return }
            error = nil
            nativeArchiveDestination = url
            settings.blocker.apply(to: view, destination: url)
            view.load(data, mimeType: "application/x-webarchive", characterEncodingName: "utf-8", baseURL: url)
            site.lastOpened = Date()
            settings.save()
        } catch { self.error = "Unable to open offline copy. \(error.localizedDescription)" }
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
