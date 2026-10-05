import Observation
import SwiftData
import Foundation

@MainActor @Observable
final class SettingsStore {
    let container: ModelContainer
    let history: HistoryStore
    private let defaults: UserDefaults
    var historyRetention: HistoryRetention {
        didSet { defaults.set(historyRetention.rawValue, forKey: "historyRetention") }
    }
    var permissions: [SitePermission] = []
    var persistenceError: String?
    let blocker = BlockerController()
    let youtube = YouTubePilot()
    var youtubeScriptletsEnabled: Bool {
        didSet {
            defaults.set(youtubeScriptletsEnabled, forKey: "youtubeScriptletsEnabled")
            blocker.applyToAll(reload: true, onlySite: "youtube.com")
        }
    }
    let energy: EnergyPolicy
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

    init(configuration: ModelConfiguration = ModelConfiguration(cloudKitDatabase: .none), defaults: UserDefaults = .standard) {
        self.defaults = defaults
        youtubeScriptletsEnabled = defaults.object(forKey: "youtubeScriptletsEnabled") as? Bool ?? true
        historyRetention = defaults.string(forKey: "historyRetention").flatMap(HistoryRetention.init(rawValue:)) ?? .year
        let controller = blocker
        energy = EnergyPolicy { [weak controller] in controller?.setWorkAllowed($0) }
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            // Browsing history and saved sites remain on this headset, without CloudKit.
            container = try ModelContainer(for: SitePermission.self, SavedSite.self, HistoryEntry.self, BrowserSessionRecord.self,
                                           configurations: configuration)
            history = HistoryStore(context: container.mainContext)
            history.prune(keeping: historyRetention)
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
        setBlockingDisabled(!blockingOffSites.contains(domain), on: domain)
    }

    func setBlockingDisabled(_ disabled: Bool, on domain: String) {
        permission(for: domain).blockingDisabled = disabled
        save()
        blocker.applyToAll(reload: true, onlySite: domain)
    }

    func allowNavigation(on domain: String, allow: Bool) {
        guard !domain.isEmpty else { return }
        permission(for: domain).allowsNavigation = allow
        save()
    }

    private func permission(for domain: String) -> SitePermission {
        if let existing = permissions.first(where: { $0.domain == domain }) { return existing }
        let permission = SitePermission(domain: domain)
        container.mainContext.insert(permission)
        permissions.append(permission)
        return permission
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
