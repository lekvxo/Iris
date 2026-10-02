import XCTest
import SwiftData
import UIKit
import WebKit
@testable import Iris

@MainActor final class HistoryRecordingTests: XCTestCase {
    func testSuccessfulPageSPAAndLateTitleExcludeBlockedAndFailedLoads() async throws {
        let settings = SettingsStore(configuration: ModelConfiguration(isStoredInMemoryOnly: true))
        let (model, coordinator, view) = try fixture(settings)
        defer { view.removeFromSuperview(); WebView.dismantleUIView(view, coordinator: coordinator) }
        let base = URL(string: "https://history.example.com/first")!
        model.url = base
        model.nativeDestination = base
        view.loadHTMLString("<html><head><title>First page</title></head><body>History fixture</body></html>", baseURL: base)
        try await wait { self.entries(settings).count == 1 }
        XCTAssertEqual(entries(settings).first?.url, base.absoluteString)
        _ = try await view.evaluateJavaScript("history.pushState({}, '', '/second'); document.title = 'Second page'; null")
        try await wait { self.entries(settings).contains { $0.url.hasSuffix("/second") && $0.title == "Second page" } }
        let secondVisit = try XCTUnwrap(entries(settings).first { $0.url.hasSuffix("/second") }).visitedAt
        _ = try await view.evaluateJavaScript("document.title = 'Late title'; null")
        try await wait { self.entries(settings).contains { $0.title == "Late title" } }
        XCTAssertEqual(entries(settings).first { $0.url.hasSuffix("/second") }?.visitedAt, secondVisit)
        _ = try await view.evaluateJavaScript("location.hash = 'part'; null")
        try await wait { self.entries(settings).contains { $0.url.hasSuffix("/second#part") } }
        _ = try await view.evaluateJavaScript("location.href = 'https://denied.example.net/'; null")
        try await wait { model.blocked != nil }
        XCTAssertEqual(entries(settings).count, 3)
        XCTAssertFalse(entries(settings).contains { $0.host == "denied.example.net" })
        model.load(URL(string: "http://127.0.0.1:1/failure")!)
        try await wait { model.error != nil }
        XCTAssertEqual(entries(settings).count, 3)
        XCTAssertNil(settings.history.error)
    }

    func testAllowedPopupRecordsInSharedHistory() async throws {
        let settings = SettingsStore(configuration: ModelConfiguration(isStoredInMemoryOnly: true))
        let (model, coordinator, view) = try fixture(settings)
        defer { view.removeFromSuperview(); WebView.dismantleUIView(view, coordinator: coordinator) }
        let base = URL(string: "https://history.example.com/opener")!
        model.url = base
        model.nativeDestination = base
        model.allowedSites = ["example.com"]
        var requests: [WindowRequest] = []
        model.openWindow = { requests.append($0) }
        view.loadHTMLString("<html><title>Opener</title><body>Popup history fixture</body></html>", baseURL: base)
        try await wait { self.entries(settings).count == 1 }
        _ = try await view.evaluateJavaScript("window.open('https://history.example.com/popup'); null")
        try await wait { !requests.isEmpty }
        let popup = try XCTUnwrap(BrowserModel.adoptPopup(requests[0].id))
        let child = try XCTUnwrap(popup.popup?.view)
        let childCoordinator = try XCTUnwrap(popup.popup?.coordinator)
        popup.popup = nil
        child.stopLoading()
        child.frame = view.frame
        view.window?.addSubview(child)
        defer { child.removeFromSuperview(); WebView.dismantleUIView(child, coordinator: childCoordinator) }
        let address = URL(string: "https://history.example.com/popup-fixture")!
        popup.nativeDestination = address
        child.loadHTMLString("<html><title>Popup page</title><body>Popup history</body></html>", baseURL: address)
        try await wait { self.entries(settings).contains { $0.url == address.absoluteString && $0.title == "Popup page" } }
        XCTAssertNil(settings.history.error)
    }

    func testOfflineReplayAndItsSamePageChangesNeverRecord() async throws {
        let settings = SettingsStore(configuration: ModelConfiguration(isStoredInMemoryOnly: true))
        let (model, coordinator, view) = try fixture(settings)
        defer { view.removeFromSuperview(); WebView.dismantleUIView(view, coordinator: coordinator) }
        let base = URL(string: "https://history.example.com/offline")!
        model.url = base
        model.nativeArchiveDestination = base
        model.archiveReplay = ("fixture.webarchive", base)
        view.loadHTMLString("<html><head><title>Offline</title></head><body id='offline'>Saved copy</body></html>", baseURL: base)
        try await wait { !view.isLoading && view.title == "Offline" }
        _ = try await view.evaluateJavaScript("history.pushState({}, '', '/offline-changed'); document.title = 'Still offline'; null")
        try await wait { view.url?.path == "/offline-changed" && view.title == "Still offline" }
        XCTAssertTrue(entries(settings).isEmpty)
    }

    private func entries(_ settings: SettingsStore) -> [HistoryEntry] {
        (try? settings.container.mainContext.fetch(FetchDescriptor<HistoryEntry>())) ?? []
    }

    private func fixture(_ settings: SettingsStore) throws -> (BrowserModel, WebView.Coordinator, WKWebView) {
        let model = BrowserModel()
        let coordinator = WebView.Coordinator(model: model)
        let view = WebView.makeWebView(WKWebViewConfiguration(), coordinator: coordinator, settings: settings)
        view.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = try XCTUnwrap(scene.windows.first(where: \.isKeyWindow))
        window.addSubview(view)
        return (model, coordinator, view)
    }

    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<450 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw FilterError.conversion("History fixture did not reach its expected state")
    }
}
