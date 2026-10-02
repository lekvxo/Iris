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
        // Cold visionOS 27 WebContent startup can exceed ten seconds.
        for _ in 0..<450 {
            if view.title == "done" { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let state = try await view.evaluateJavaScript("JSON.stringify({ready:document.readyState,hidden:document.hidden,title:document.title,mutations:document.querySelectorAll('#feed span').length})")
        XCTAssertEqual(view.title, "done", "Fixture state: \(String(describing: state)); scene: \(scene.activationState.rawValue)")
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertGreaterThanOrEqual(counter.count, 1, "The video must still be reported")
        XCTAssertLessThanOrEqual(counter.count, 3, "Unchanged video state must not be re-sent on every mutation")
        _ = try await view.evaluateJavaScript("window.postMessage({type:'iris-video-policy',enabled:false,interval:250}, '*')")
        try await Task.sleep(for: .milliseconds(300))
        let before = counter.count
        _ = try await view.evaluateJavaScript("document.querySelector('video').src='https://video.example.com/new.mp4'; document.querySelector('video').dispatchEvent(new Event('loadedmetadata'))")
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(counter.count, before, "Background detection must send no reports")
        _ = try await view.evaluateJavaScript("window.postMessage({type:'iris-video-policy',enabled:true,interval:250}, '*')")
        for _ in 0..<30 {
            if counter.count > before { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertGreaterThan(counter.count, before, "Foreground detection must catch state changed while suspended")
    }
}
