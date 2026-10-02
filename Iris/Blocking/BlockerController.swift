import Observation
import WebKit

@MainActor @Observable
final class BlockerController {
    var isUpdating = false
    var isReady = false
    var lastUpdated: Date?
    var ruleCount = 0
    var status: String?
    private let engine = BlockerEngine()
    @ObservationIgnored private var lists: [WKContentRuleList] = []
    @ObservationIgnored private var startup: Task<Void, Never>?
    @ObservationIgnored private weak var settings: SettingsStore?
    @ObservationIgnored private var views: [WeakView] = []
    @ObservationIgnored private var revision = 0
    private final class WeakView {
        weak var view: WKWebView?
        var enabled: Bool?
        var revision = -1
        init(_ view: WKWebView) { self.view = view }
    }

    func register(_ view: WKWebView, settings: SettingsStore) async {
        self.settings = settings
        views.removeAll { $0.view == nil }
        views.append(WeakView(view))
        if startup == nil {
            startup = Task { await prepare() }
        }
        await startup?.value
        apply(to: view, destination: view.url)
    }

    func unregister(_ view: WKWebView) { views.removeAll { $0.view == nil || $0.view === view } }

    private func prepare() async {
        do {
            if let cache = try await engine.cached(), try await install(cache) {
                if cache.needsRefresh() { Task { await refresh() } }
                return
            }
        } catch { status = error.localizedDescription }
        await refresh()
    }

    func refresh() async {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }
        do {
            let manifest = try await engine.refresh()
            guard try await install(manifest) else { throw FilterError.conversion("Compiled cache is unavailable") }
            status = nil
            let active = Set(manifest.identifiers)
            for id in await WKContentRuleListStore.default().availableIdentifiers() ?? [] where id.hasPrefix("iris-") && !active.contains(id) {
                try? await WKContentRuleListStore.default().removeContentRuleList(forIdentifier: id)
            }
        } catch { status = error.localizedDescription }
    }

    private func install(_ manifest: BlockerEngine.Manifest) async throws -> Bool {
        var resolved: [WKContentRuleList] = []
        for id in manifest.identifiers {
            guard let list = try await WKContentRuleListStore.default().contentRuleList(forIdentifier: id) else { return false }
            resolved.append(list)
        }
        guard !resolved.isEmpty else { return false }
        lists = resolved
        revision += 1
        lastUpdated = manifest.updatedAt
        ruleCount = manifest.ruleCount
        isReady = true
        applyToAll()
        return true
    }

    func apply(to view: WKWebView, destination: URL?) {
        let enabled = settings?.blockingActive(for: destination) != false
        if let entry = views.first(where: { $0.view === view }) {
            if entry.enabled == enabled, entry.revision == revision { return }
            entry.enabled = enabled
            entry.revision = revision
        }
        view.configuration.userContentController.removeAllContentRuleLists()
        guard enabled else { return }
        for list in lists { view.configuration.userContentController.add(list) }
    }

    func applyToAll(reload: Bool = false, onlySite: String? = nil) {
        views.removeAll { $0.view == nil }
        for item in views {
            if let view = item.view {
                apply(to: view, destination: view.url)
                let site = view.url?.host.map(PublicSuffix.bundled.registrableDomain)
                if reload, view.url != nil, onlySite == nil || onlySite == site { view.reload() }
            }
        }
    }
}
