import XCTest
import WebKit
import UIKit
@testable import Iris

@MainActor final class NativeCaptionsTests: XCTestCase {
    func testNativeCueSafeAreaRestoresWebsitePositionAndRespectsCaptionOff() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(WKUserScript(source: ScriptSource.read("NativeCaptions"), injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = try XCTUnwrap(scene.windows.first)
        window.addSubview(view)
        defer { view.stopLoading(); view.removeFromSuperview() }
        view.loadHTMLString("<html><body><video id='v'></video></body></html>", baseURL: URL(string: "https://caption.example"))
        for _ in 0..<450 {
            if let ready = try? await view.evaluateJavaScript("typeof window.irisPrepareNativeCaptions === 'function'"), ready as? Bool == true { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let result = try await view.evaluateJavaScript("""
            (() => {
                const v = document.getElementById('v');
                const track = v.addTextTrack('subtitles', 'English', 'en');
                const cue = new VTTCue(0, 100, 'Visible caption');
                cue.line = 98; cue.snapToLines = false; cue.position = 90; cue.size = 65;
                track.addCue(cue); track.mode = 'showing';
                const preference = window.irisNativeCaptionPreference(v);
                window.irisPrepareNativeCaptions(v);
                const safe = cue.line === -3 && cue.snapToLines && cue.position === 50 && cue.size === 90;
                v.dispatchEvent(new Event('webkitendfullscreen'));
                const restored = cue.line === 98 && !cue.snapToLines && cue.position === 90 && cue.size === 65;
                window.irisPrepareNativeCaptions(v);
                track.mode = 'disabled';
                v.dispatchEvent(new Event('webkitendfullscreen'));
                return {safe, restored, off: track.mode === 'disabled', language: preference.language, enabled: preference.enabled};
            })()
            """) as? [String: Any]
        XCTAssertEqual(result?["safe"] as? Bool, true)
        XCTAssertEqual(result?["restored"] as? Bool, true)
        XCTAssertEqual(result?["off"] as? Bool, true)
        XCTAssertEqual(result?["enabled"] as? Bool, true)
        XCTAssertEqual(result?["language"] as? String, "en")
        let disabled = try await view.evaluateJavaScript("window.irisNativeCaptionPreference(document.getElementById('v')).enabled")
        XCTAssertEqual(disabled as? Bool, false, "A disabled track must not be switched on")
    }

    func testContainerRepinsWebViewAfterFullscreenReparenting() {
        let model = BrowserModel()
        let view = WKWebView()
        let container = BrowserWebContainer(webView: view, model: model)
        container.frame = CGRect(x: 0, y: 0, width: 900, height: 600)
        container.layoutIfNeeded()
        view.removeFromSuperview()
        let fullscreen = UIView(frame: CGRect(x: 0, y: 0, width: 1600, height: 900))
        fullscreen.addSubview(view)
        view.frame = fullscreen.bounds
        view.removeFromSuperview()
        container.addSubview(view)
        container.frame.size = CGSize(width: 1100, height: 720)
        container.setNeedsLayout()
        container.layoutIfNeeded()
        XCTAssertEqual(view.frame, container.bounds, "Fullscreen's frame must not remain stuck after returning")
    }
}
