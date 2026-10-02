import XCTest
import WebKit
import UIKit
@testable import Iris

@MainActor final class VideoProbeTests: XCTestCase {
    private final class Counter: NSObject, WKScriptMessageHandler {
        var count = 0
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            count += 1
        }
    }

    func testBusyPageSendsFewVideoReports() async throws {
        let counter = Counter()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(counter, name: "irisVideo")
        configuration.userContentController.addUserScript(WKUserScript(
            source: ScriptSource.read("VideoProbe"), injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        // An offscreen web view throttles timers, so host it in a visible window.
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        host.view = view
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            configuration.userContentController.removeScriptMessageHandler(forName: "irisVideo")
        }
        // 1,000 DOM mutations over about a second, the pattern that used to post one report per mutation.
        view.loadHTMLString("""
            <html><body><video></video><div id='feed'></div><script>
            let n = 0;
            const id = setInterval(() => {
                for (let i = 0; i < 20; i++) document.getElementById('feed').appendChild(document.createElement('span'));
                if (++n === 50) { clearInterval(id); document.title = 'done'; }
            }, 20);
            </script></body></html>
            """, baseURL: URL(string: "https://video.example.com"))
        for _ in 0..<100 {
            if view.title == "done" { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(view.title, "done")
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertGreaterThanOrEqual(counter.count, 1, "The video must still be reported")
        XCTAssertLessThanOrEqual(counter.count, 3, "Unchanged video state must not be re-sent on every mutation")
    }
}
