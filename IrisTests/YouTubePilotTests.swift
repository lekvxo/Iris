import XCTest
import SwiftData
import WebKit
import UIKit
import ContentBlockerConverter
@testable import Iris

@MainActor final class YouTubePilotTests: XCTestCase {
    func testQuotedRegexAndEscapedCommaRoundTrip() throws {
        let raw = #"www.youtube.com##+js(trusted-replace-xhr-response, /"adPlacements.*?([A-Z]"\}|"\}{2\,4})\}\]\,/, , /playlist\?list=|\/player(?:\?.+)?$|watch\?[tv]=/)"#
        let canonical = try XCTUnwrap(YouTubeRuleAdapter.rewrite(raw))
        let call = try XCTUnwrap(YouTubeRuleAdapter.call(String(canonical.split(separator: "#").last!)))
        XCTAssertEqual(call.runtimeName, "trusted-replace-xhr-response")
        XCTAssertEqual(call.args[0], #"/"adPlacements.*?([A-Z]"\}|"\}{2,4})\}\],/"#)
        XCTAssertEqual(call.args[1], "")
        XCTAssertEqual(call.args[2], #"/playlist\?list=|\/player(?:\?.+)?$|watch\?[tv]=/"#)
        let second = #"www.youtube.com##+js(trusted-replace-xhr-response, /"adPlacements.*?("adSlots"|"adBreakHeartbeatParams")/gms, $1, /\/player(?:\?.+)?$/)"#
        let repaired = try XCTUnwrap(YouTubeRuleAdapter.rewrite(second))
        let parsed = try XCTUnwrap(YouTubeRuleAdapter.call(String(repaired.split(separator: "#").last!)))
        XCTAssertEqual(parsed.args[0], #"/"adPlacements.*?("adSlots"|"adBreakHeartbeatParams")/gms"#)
        XCTAssertEqual(parsed.args[1], "$1")
        XCTAssertThrowsError(try YouTubeRuleAdapter.arguments("set, 'unclosed"))
    }

    func testOnlyReviewedAliasesAndYouTubeHostsAreAccepted() {
        XCTAssertEqual(YouTubeRuleAdapter.runtimeName(for: "ubo-trusted-replace-fetch-response"), "trusted-replace-fetch-response")
        XCTAssertEqual(YouTubeRuleAdapter.runtimeName(for: "ubo-trusted-replace-xhr-response"), "trusted-replace-xhr-response")
        XCTAssertEqual(YouTubeRuleAdapter.runtimeName(for: "ubo-set"), "ubo-set")
        XCTAssertNil(YouTubeRuleAdapter.runtimeName(for: "ubo-arbitrary-script"))
        for host in ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com"] {
            XCTAssertTrue(YouTubeRuleAdapter.contains(URL(string: "https://\(host)/watch")))
        }
        for url in ["https://youtube.com.evil.test", "https://evilyoutube.com", "https://youtube-nocookie.com", "file://youtube.com/watch"] {
            XCTAssertFalse(YouTubeRuleAdapter.contains(URL(string: url)))
        }
    }

    func testActualBundledRulesParseAndMatchWithExceptions() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = YouTubeRuleStore(root: root)
        let desktop = try await store.calls(for: URL(string: "https://www.youtube.com/watch?v=fixture")!)
        XCTAssertEqual(desktop.count, 11)
        XCTAssertEqual(desktop.filter { $0.name.hasPrefix("ubo-trusted-") }.count, 4)
        let mobile = try await store.calls(for: URL(string: "https://m.youtube.com/watch?v=fixture")!)
        XCTAssertEqual(mobile.count, 7)
        let unrelated = try await store.calls(for: URL(string: "https://example.com")!)
        XCTAssertTrue(unrelated.isEmpty)
        await store.refresh(from: [#"www.youtube.com##+js(set, fixture.flag, undefined)"#, "@@||www.youtube.com^$jsinject"])
        let excepted = try await store.calls(for: URL(string: "https://www.youtube.com/watch")!)
        XCTAssertTrue(excepted.isEmpty, "Network exceptions must suppress scriptlets")
        await store.refresh(from: [#"www.youtube.com##+js(set, 'unclosed)"#])
        let retained = try await store.calls(for: URL(string: "https://www.youtube.com/watch")!)
        XCTAssertTrue(retained.isEmpty, "A failed rule update must retain the last working exceptions")
    }

    func testToggleDefaultsOnAndPersistsIndependently() throws {
        let suite = "iris-youtube-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(configuration: ModelConfiguration(isStoredInMemoryOnly: true), defaults: defaults)
        XCTAssertTrue(settings.youtubeScriptletsEnabled)
        settings.youtubeScriptletsEnabled = false
        let reopened = SettingsStore(configuration: ModelConfiguration(isStoredInMemoryOnly: true), defaults: defaults)
        XCTAssertFalse(reopened.youtubeScriptletsEnabled)
        XCTAssertEqual(reopened.blockingEnabled, settings.blockingEnabled)
    }

    func testPinnedRuntimeRepairsFetchAndXHRWithoutChangingVideoData() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let pilot = YouTubePilot(store: YouTubeRuleStore(root: root))
        let prepared = try await pilot.source(for: URL(string: "https://youtube.com/watch?v=fixture")!, enabled: true)
        let source = try XCTUnwrap(prepared)
        let reports = Reports()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(reports, name: "irisYouTubeScriptlets")
        configuration.userContentController.addUserScript(WKUserScript(source: Self.networkFixture, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = try XCTUnwrap(scene.windows.first(where: \.isKeyWindow))
        window.addSubview(view)
        defer { pilot.install(nil, in: view); view.removeFromSuperview(); configuration.userContentController.removeScriptMessageHandler(forName: "irisYouTubeScriptlets") }
        pilot.install(source, in: view)
        view.loadHTMLString("<html><body id='fixture'>YouTube response fixture</body></html>", baseURL: URL(string: "https://www.youtube.com/watch?v=fixture")!)
        for _ in 0..<450 {
            if !view.isLoading, !reports.values.isEmpty { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let report = try XCTUnwrap(reports.values.first)
        XCTAssertEqual(report["version"] as? String, "2.3.1")
        XCTAssertEqual((report["ran"] as? [String])?.count, 11)
        XCTAssertEqual((report["failed"] as? [String])?.count, 0)
        let fetch = try await view.callAsyncJavaScript("return JSON.parse(await (await fetch('https://www.youtube.com/player?fixture')).text());", arguments: [:], in: nil, contentWorld: .page) as? [String: Any]
        XCTAssertNil(fetch?["adPlacements"])
        XCTAssertNil(fetch?["adSlots"])
        XCTAssertEqual((fetch?["videoDetails"] as? [String: String])?["title"], "Actual video")
        let xhr = try await view.callAsyncJavaScript("return await new Promise(resolve => { const xhr = new XMLHttpRequest(); xhr.addEventListener('load', () => resolve(JSON.parse(xhr.responseText))); xhr.open('GET', 'https://www.youtube.com/player?fixture'); xhr.send(); });", arguments: [:], in: nil, contentWorld: .page) as? [String: Any]
        XCTAssertNil(xhr?["adPlacements"], "The repaired regex and XHR alias must actually replace the matching response")
        XCTAssertEqual((xhr?["videoDetails"] as? [String: String])?["title"], "Actual video")
        // Disable before reload: remove only the owned script and restore a clean document.
        pilot.install(nil, in: view)
        XCTAssertEqual(configuration.userContentController.userScripts.count, 1, "Other app scripts must remain")
        view.loadHTMLString("<html><body id='fixture'>Off</body></html>", baseURL: URL(string: "https://www.youtube.com/watch?v=fixture")!)
        try await Task.sleep(for: .seconds(1))
        let unfiltered = try await view.callAsyncJavaScript("return JSON.parse(await (await fetch('https://www.youtube.com/player?fixture')).text());", arguments: [:], in: nil, contentWorld: .page) as? [String: Any]
        XCTAssertNotNil(unfiltered?["adPlacements"])
        XCTAssertNotNil(unfiltered?["adSlots"])
        // Even a stale script carried through a redirect must not execute on a lookalike host.
        pilot.install(source, in: view)
        let reportCount = reports.values.count
        view.loadHTMLString("<html><body>Lookalike</body></html>", baseURL: URL(string: "https://youtube.com.evil.test/watch")!)
        try await Task.sleep(for: .seconds(1))
        let lookalike = try await view.callAsyncJavaScript("return JSON.parse(await (await fetch('https://www.youtube.com/player?fixture')).text());", arguments: [:], in: nil, contentWorld: .page) as? [String: Any]
        XCTAssertNotNil(lookalike?["adPlacements"])
        XCTAssertEqual(reports.values.count, reportCount)
        let off = try await pilot.source(for: URL(string: "https://www.youtube.com")!, enabled: false)
        let unrelated = try await pilot.source(for: URL(string: "https://example.com")!, enabled: true)
        XCTAssertNil(off)
        XCTAssertNil(unrelated)
    }

    private final class Reports: NSObject, WKScriptMessageHandler {
        var values: [[String: Any]] = []
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if let body = message.body as? [String: Any] { values.append(body) }
        }
    }

    private static let networkFixture = """
    (() => {
      const payload = '{"adPlacements":[{"ad":"Advert"}],"adSlots":[{"ad":"Advert"}],"videoDetails":{"title":"Actual video"}}';
      window.fetch = async () => new Response(payload, {status:200, headers:{'Content-Type':'application/json'}});
      class FixtureXHR extends EventTarget {
        constructor() { super(); this.readyState=0; this.responseType=''; this.withCredentials=false; }
        open(method,url) { this.responseURL=url; this.readyState=1; }
        setRequestHeader() {}
        getAllResponseHeaders() { return 'Content-Type: application/json'; }
        getResponseHeader() { return 'application/json'; }
        send() { queueMicrotask(() => {
          this.readyState=4; this.status=200; this.statusText='OK'; this.responseText=payload; this.response=payload; this.responseXML=null;
          this.dispatchEvent(new Event('readystatechange')); this.dispatchEvent(new Event('load')); this.dispatchEvent(new Event('loadend'));
        }); }
      }
      window.XMLHttpRequest = FixtureXHR;
    })();
    """
}
