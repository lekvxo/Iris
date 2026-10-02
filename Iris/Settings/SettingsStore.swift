import Observation
import SwiftData
import Foundation

@MainActor @Observable
final class SettingsStore {
    let container: ModelContainer
    var permissions: [SitePermission] = []
    var persistenceError: String?
    let blocker = BlockerController()

    init() {
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            container = try ModelContainer(for: SitePermission.self)
            permissions = try container.mainContext.fetch(FetchDescriptor<SitePermission>(sortBy: [SortDescriptor(\.domain)]))
        } catch {
            fatalError("Iris could not open its saved data: \(error.localizedDescription)")
        }
    }

    var navigationSites: Set<String> {
        Set(permissions.filter(\.allowsNavigation).map(\.domain))
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

    func save() {
        do { try container.mainContext.save(); persistenceError = nil }
        catch { persistenceError = error.localizedDescription }
    }
}
