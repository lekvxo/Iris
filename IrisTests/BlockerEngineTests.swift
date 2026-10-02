import XCTest
import WebKit
import UIKit
@testable import Iris

final class BlockerEngineTests: XCTestCase {
    func testHostsListTranslation() {
        let text = "# license\n127.0.0.1 ads.example\n0.0.0.0 tracker.example\n127.0.0.1 localhost\n127.0.0.1 invalid/domain\n"
        XCTAssertEqual(FilterLists.normalized(text, hostsFormat: true), ["||ads.example^", "||tracker.example^"])
    }

    func testWeeklyRefreshBoundary() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        let manifest = BlockerEngine.Manifest(identifiers: ["fixture"], updatedAt: date, ruleCount: 1, conversionSeconds: 0, compilationSeconds: 0)
        XCTAssertFalse(manifest.needsRefresh(now: date.addingTimeInterval(604799)))
        XCTAssertTrue(manifest.needsRefresh(now: date.addingTimeInterval(604800)))
    }

    @MainActor func testShardsCompileAndPreserveCrossListExceptions() async throws {
        let result = try await BlockerEngine().convert(rules: ["||ads.example^", "||tracker.example^", "@@||ads.example^$domain=allowed.example"], chunkSize: 1)
        XCTAssertEqual(result.json.count, 2)
        for (index, json) in result.json.enumerated() {
            let rules = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
            XCTAssertTrue(rules.contains { ($0["action"] as? [String: String])?["type"] == "ignore-previous-rules" })
            let identifier = "iris-test-\(UUID().uuidString)-\(index)"
            let list = try await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json)
            XCTAssertNotNil(list)
            try await WKContentRuleListStore.default().removeContentRuleList(forIdentifier: identifier)
        }
    }

    @MainActor func testCosmeticBlockingAndRemovalInWebKit() async throws {
        let result = try await BlockerEngine().convert(rules: ["example.com##.advert"])
        let identifier = "iris-test-\(UUID().uuidString)"
        let compiled = try await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: result.json[0])
        let list = try XCTUnwrap(compiled)
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        host.view = view
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        view.configuration.userContentController.add(list)
        let html = "<html><body><div class='advert' id='advert'>Ad</div></body></html>"
        view.loadHTMLString(html, baseURL: URL(string: "https://example.com")!)
        let hidden = try await displayStyle(view)
        XCTAssertEqual(hidden, "none")
        view.configuration.userContentController.removeAllContentRuleLists()
        view.loadHTMLString(html, baseURL: URL(string: "https://example.com")!)
        // Wait for a new document to finish, not the previous computed style.
        try await Task.sleep(for: .milliseconds(500))
        let visible = try await displayStyle(view)
        XCTAssertEqual(visible, "block")
        try await WKContentRuleListStore.default().removeContentRuleList(forIdentifier: identifier)
    }

    @MainActor private func displayStyle(_ view: WKWebView) async throws -> String {
        for _ in 0..<150 {
            if !view.isLoading, let result = try? await view.evaluateJavaScript("document.getElementById('advert') ? getComputedStyle(document.getElementById('advert')).display : null"),
               let text = result as? String { return text }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw FilterError.conversion("Fixture did not load")
    }
}
