import SwiftData
import WebKit

extension BrowserModel {
    func openArchive(_ site: SavedSite, settings: SettingsStore) async {
        guard let name = site.archiveFileName, let url = URL(string: site.url) else { return }
        do {
            try await loadArchive(name, url: url, settings: settings)
            site.lastOpened = Date()
            settings.save()
        } catch { self.error = "Unable to open offline copy. \(error.localizedDescription)" }
    }

    private func loadArchive(_ name: String, url: URL, settings: SettingsStore) async throws {
        guard let view = webView else { throw SavedError.pageChanged }
        let document = documentID
        let data = try await settings.archives.read(name)
        guard webView === view, documentID == document else { throw SavedError.pageChanged }
        invalidateVideo()
        error = nil
        requestedURL = url
        archiveReplay = (name, url)
        nativeArchiveDestination = url
        settings.blocker.apply(to: view, destination: url)
        view.load(data, mimeType: "application/x-webarchive", characterEncodingName: "utf-8", baseURL: url)
    }

    func retryPage(settings: SettingsStore) async {
        if let archiveReplay {
            do { try await loadArchive(archiveReplay.name, url: archiveReplay.url, settings: settings) }
            catch { self.error = "Unable to reopen offline copy. \(error.localizedDescription)" }
        } else if let url = requestedURL ?? url { load(url) }
    }

    func reloadPage(settings: SettingsStore) async {
        if archiveReplay != nil { await retryPage(settings: settings) }
        else { invalidateVideo(); webView?.reload() }
    }

    func saveOffline(existing: SavedSite?, settings: SettingsStore) async {
        guard !isSavingOffline, let view = webView, let url = view.url else { return }
        isSavingOffline = true
        saveError = nil
        defer { isSavingOffline = false }
        let site = existing ?? SavedSite(url: url, title: title)
        do {
            let data = try await view.irisArchiveData()
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
