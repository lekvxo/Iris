import Foundation
import Observation
import WebKit

@MainActor @Observable
final class BrowserTab: Identifiable {
    let id: UUID
    let model: BrowserModel
    let initialURL: URL
    var isPinned: Bool
    var hasBeenSelected = false

    init(url: URL, model: BrowserModel = BrowserModel(), id: UUID = UUID(), pinned: Bool = false) {
        self.id = id
        self.model = model
        initialURL = url
        isPinned = pinned
    }

    var title: String { model.title == "Iris" ? initialURL.host ?? "New tab" : model.title }
}

@MainActor @Observable
final class BrowserTabs {
    static let home = URL(string: "https://www.google.com")!
    private(set) var tabs: [BrowserTab]
    private(set) var selectedID: UUID
    var selected: BrowserTab { tabs.first { $0.id == selectedID } ?? tabs[0] }
    var ordered: [BrowserTab] { tabs.filter(\.isPinned) + tabs.filter { !$0.isPinned } }

    init(url: URL? = nil, popupID: UUID? = nil) {
        let tab = BrowserTab(url: url ?? Self.home, model: popupID.flatMap(BrowserModel.adoptPopup) ?? BrowserModel())
        tabs = [tab]
        selectedID = tab.id
        tab.hasBeenSelected = true
        connect(tab)
    }

    @discardableResult func open(_ request: WindowRequest = WindowRequest(url: home)) -> BrowserTab {
        let tab = BrowserTab(url: request.url, model: BrowserModel.adoptPopup(request.id) ?? BrowserModel())
        tabs.append(tab)
        connect(tab)
        select(tab.id)
        return tab
    }

    func select(_ id: UUID) {
        guard id != selectedID, tabs.contains(where: { $0.id == id }) else { return }
        let previous = selected.model
        previous.isBackgrounded = true
        // A hidden tab must not leave video/audio playing or keep its detector busy.
        previous.webView?.evaluateJavaScript("window.postMessage({type:'iris-tab-hidden'}, '*')", completionHandler: nil)
        previous.playerSession?.stop()
        selectedID = id
        selected.hasBeenSelected = true
        selected.model.isBackgrounded = false
        updatePolicy(previous)
        updatePolicy(selected.model)
    }

    func close(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs[index]
        tab.model.popup = nil
        tab.model.invalidateVideo()
        tab.model.webView?.stopLoading()
        if let view = tab.model.webView, let coordinator = view.navigationDelegate as? WebView.Coordinator {
            WebView.dismantleUIView(view, coordinator: coordinator)
        }
        tabs.remove(at: index)
        if tabs.isEmpty {
            let replacement = BrowserTab(url: Self.home)
            tabs = [replacement]
            connect(replacement)
        }
        if selectedID == id {
            selectedID = tabs[min(index, tabs.count - 1)].id
            selected.hasBeenSelected = true
            selected.model.isBackgrounded = false
            updatePolicy(selected.model)
        }
    }

    private func connect(_ tab: BrowserTab) {
        tab.model.openWindow = { [weak self] in self?.open($0) }
        tab.model.closeWindow = { [weak self, weak tab] in
            guard let tab else { return }
            self?.close(tab.id)
        }
    }

    private func updatePolicy(_ model: BrowserModel) {
        if let view = model.webView, let coordinator = view.navigationDelegate as? WebView.Coordinator {
            coordinator.updateVideoPolicy(view)
        }
    }

    private struct Snapshot: Codable {
        struct Tab: Codable { let id: UUID; let url: URL; let pinned: Bool }
        let tabs: [Tab]
        let selected: UUID
    }

    var snapshot: String {
        let value = Snapshot(tabs: tabs.map { .init(id: $0.id, url: $0.model.url ?? $0.initialURL, pinned: $0.isPinned) }, selected: selectedID)
        return (try? JSONEncoder().encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    func restore(_ text: String) {
        guard let data = text.data(using: .utf8), let value = try? JSONDecoder().decode(Snapshot.self, from: data),
              !value.tabs.isEmpty, value.tabs.count <= 100,
              Set(value.tabs.map(\.id)).count == value.tabs.count,
              value.tabs.allSatisfy({ ["http", "https"].contains($0.url.scheme?.lowercased() ?? "") && $0.url.host != nil }) else { return }
        tabs = value.tabs.map { BrowserTab(url: $0.url, id: $0.id, pinned: $0.pinned) }
        selectedID = tabs.contains { $0.id == value.selected } ? value.selected : tabs[0].id
        for tab in tabs {
            connect(tab)
            tab.model.isBackgrounded = tab.id != selectedID
            tab.hasBeenSelected = tab.id == selectedID
        }
    }
}
