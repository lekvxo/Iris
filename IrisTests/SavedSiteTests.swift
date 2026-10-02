import XCTest
import SwiftData
import UIKit
import WebKit
@testable import Iris

final class SavedSiteTests: XCTestCase {
    @MainActor func testSavedSitesAndSiteExceptionsSurviveReopening() throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema([SavedSite.self, SitePermission.self])
        let configuration = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("test.store"))
        var identifier: UUID!
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let site = SavedSite(url: URL(string: "https://example.com/article")!, title: "Example", note: "Read later")
            identifier = site.id
            site.archiveFileName = site.id.uuidString + ".webarchive"
            site.title = "Renamed"
            site.lastOpened = Date(timeIntervalSince1970: 100)
            container.mainContext.insert(site)
            container.mainContext.insert(SitePermission(domain: "example.com", allowsNavigation: true, blockingDisabled: true))
            try container.mainContext.save()
        }
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let site = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<SavedSite>()).first)
            XCTAssertEqual(site.id, identifier)
            XCTAssertEqual(site.title, "Renamed")
            XCTAssertEqual(site.note, "Read later")
            XCTAssertEqual(site.lastOpened, Date(timeIntervalSince1970: 100))
            XCTAssertNotNil(site.archiveFileName)
            let permission = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<SitePermission>()).first)
            XCTAssertTrue(permission.allowsNavigation)
            XCTAssertTrue(permission.blockingDisabled)
            container.mainContext.delete(site)
            try container.mainContext.save()
        }
        let reopened = try ModelContainer(for: schema, configurations: [configuration])
        XCTAssertTrue(try reopened.mainContext.fetch(FetchDescriptor<SavedSite>()).isEmpty)
    }

    func testArchiveRoundTripDeletionAndPathValidation() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ArchiveStore(directory: directory)
        let data = Data("fixture".utf8)
        let name = try await store.write(data, id: UUID())
        let restored = try await store.read(name)
        XCTAssertEqual(data, restored)
        try await store.delete(name)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path))
        do { _ = try await store.read("../../secret.webarchive"); XCTFail("Traversal accepted") }
        catch { XCTAssertEqual((error as NSError).code, CocoaError.fileReadInvalidFileName.rawValue) }
    }

    @MainActor func testWebArchiveReopensThroughGuardWithoutNetwork() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        let original = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        host.view = original
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let base = URL(string: "https://offline.example.com/page")!
        original.loadHTMLString("<html><body><h1 id='saved'>Offline fixture</h1></body></html>", baseURL: base)
        let text = try await fixtureText(original)
        XCTAssertEqual(text, "Offline fixture")
        let archive = try await original.irisArchiveData()
        XCTAssertGreaterThan(archive.count, 100)
        let restored = WKWebView(frame: original.frame)
        host.view = restored
        let model = BrowserModel()
        model.webView = restored
        model.nativeArchiveDestination = base
        let coordinator = WebView.Coordinator(model: model)
        restored.navigationDelegate = coordinator
        restored.load(archive, mimeType: "application/x-webarchive", characterEncodingName: "utf-8", baseURL: base)
        let reopened = try await fixtureText(restored)
        XCTAssertEqual(reopened, "Offline fixture")
        XCTAssertNil(model.blocked)
    }

    @MainActor private func fixtureText(_ view: WKWebView) async throws -> String {
        for _ in 0..<150 {
            if !view.isLoading, let value = try? await view.evaluateJavaScript("document.getElementById('saved')?.textContent"), let text = value as? String { return text }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw SavedError.pageChanged
    }
}
