import Observation
import SwiftData
import Foundation

@MainActor @Observable
final class SettingsStore {
    let container: ModelContainer
    var permissions: [SitePermission] = []
    var persistenceError: String?
    let blocker = BlockerController()
    let archives = ArchiveStore()
    var nativeVideo = UserDefaults.standard.object(forKey: "nativeVideo") as? Bool ?? true {
        didSet { UserDefaults.standard.set(nativeVideo, forKey: "nativeVideo") }
    }
    var blockingEnabled = UserDefaults.standard.object(forKey: "blockingEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(blockingEnabled, forKey: "blockingEnabled")
            blocker.applyToAll(reload: true)
        }
    }

    init() {
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            container = try ModelContainer(for: SitePermission.self, SavedSite.self)
            permissions = try container.mainContext.fetch(FetchDescriptor<SitePermission>(sortBy: [SortDescriptor(\.domain)]))
        } catch {
            fatalError("Iris could not open its saved data: \(error.localizedDescription)")
        }
    }

    var navigationSites: Set<String> {
        Set(permissions.filter(\.allowsNavigation).map(\.domain))
    }

    var blockingOffSites: Set<String> {
        Set(permissions.filter(\.blockingDisabled).map(\.domain))
    }

    func blockingActive(for url: URL?) -> Bool {
        guard blockingEnabled else { return false }
        let site = url?.host.map(PublicSuffix.bundled.registrableDomain) ?? ""
        return !blockingOffSites.contains(site)
    }

    func toggleBlocking(for url: URL?) {
        guard let host = url?.host else { return }
        let domain = PublicSuffix.bundled.registrableDomain(host)
        let permission = permissions.first { $0.domain == domain } ?? SitePermission(domain: domain)
        if !permissions.contains(where: { $0 === permission }) {
            container.mainContext.insert(permission)
            permissions.append(permission)
        }
        permission.blockingDisabled.toggle()
        save()
        blocker.applyToAll(reload: true, onlySite: domain)
    }

    func allowNavigation(on domain: String, allow: Bool) {
        guard !domain.isEmpty else { return }
        let permission = permissions.first { $0.domain == domain } ?? SitePermission(domain: domain)
        if !permissions.contains(where: { $0 === permission }) {
            container.mainContext.insert(permission)
            permissions.append(permission)
        }
        permission.allowsNavigation = allow
        save()
    }

    // Removes a saved site and its offline copy. Returns an error message on failure.
    func removeSaved(_ site: SavedSite) async -> String? {
        do {
            if let name = site.archiveFileName { try await archives.delete(name) }
            container.mainContext.delete(site)
            save()
            return persistenceError
        } catch { return error.localizedDescription }
    }

    func save() {
        do { try container.mainContext.save(); persistenceError = nil }
        catch { persistenceError = error.localizedDescription }
    }
}
