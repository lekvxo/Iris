import XCTest
import WebKit
import UIKit
import AVFoundation
@testable import Iris

@MainActor final class NativeCaptionsTests: XCTestCase {
    func testBaselineLeavesFullscreenAPIsAndWebsiteTracksUntouched() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(WKUserScript(source: """
            window.originalFullscreen = {
                video: HTMLVideoElement.prototype.webkitEnterFullscreen,
                request: Element.prototype.requestFullscreen,
                presentation: HTMLVideoElement.prototype.webkitSetPresentationMode
            };
            """, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        configuration.userContentController.addUserScript(WKUserScript(source: ScriptSource.read("NativeCaptions"), injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = try XCTUnwrap(scene.windows.first)
        window.addSubview(view)
        defer { view.stopLoading(); view.removeFromSuperview() }
        view.loadHTMLString("<html><body><media-player id='p' data-media-player data-captions><video id='v'></video></media-player></body></html>", baseURL: URL(string: "https://caption.example"))
        var ready = false
        for _ in 0..<450 {
            if let value = try? await view.evaluateJavaScript("typeof window.irisNativeCaptionPreference === 'function'"), value as? Bool == true { ready = true; break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(ready)
        let result = try await view.evaluateJavaScript("""
            (() => {
                const v = document.getElementById('v'), p = document.getElementById('p');
                const en = v.addTextTrack('subtitles', 'English', 'en');
                const cue = new VTTCue(0, 100, 'Fixture subtitle');
                cue.line = 98; cue.snapToLines = false; cue.position = 90; cue.size = 65;
                en.addCue(cue); en.mode = 'hidden';
                v.dispatchEvent(new Event('webkitbeginfullscreen'));
                const hidden = en.mode === 'hidden';
                en.mode = 'showing'; v.textTracks.dispatchEvent(new Event('change'));
                v.dispatchEvent(new Event('webkitendfullscreen'));
                const showing = en.mode === 'showing';
                en.mode = 'disabled';
                Object.defineProperty(document, 'fullscreenElement', {configurable: true, value: p});
                document.dispatchEvent(new Event('fullscreenchange'));
                const ja = v.addTextTrack('subtitles', 'Japanese', 'ja'); ja.mode = 'hidden';
                v.textTracks.dispatchEvent(new Event('addtrack'));
                const late = en.mode === 'disabled' && ja.mode === 'hidden';
                Object.defineProperty(document, 'fullscreenElement', {configurable: true, value: null});
                document.dispatchEvent(new Event('fullscreenchange'));
                window.dispatchEvent(new Event('pagehide'));
                return {
                    apis: originalFullscreen.video === HTMLVideoElement.prototype.webkitEnterFullscreen &&
                        originalFullscreen.request === Element.prototype.requestFullscreen &&
                        originalFullscreen.presentation === HTMLVideoElement.prototype.webkitSetPresentationMode,
                    noBridge: !v.querySelector('track') && v.textTracks.length === 2 &&
                        typeof window.irisPrepareNativeCaptions === 'undefined',
                    controls: !v.controls && !p.hasAttribute('controls'), hidden, showing, late,
                    cues: cue.line === 98 && !cue.snapToLines && cue.position === 90 && cue.size === 65 && cue.text === 'Fixture subtitle',
                    off: en.mode === 'disabled' && ja.mode === 'hidden'
                };
            })()
            """) as? [String: Any]
        for key in ["apis", "noBridge", "controls", "hidden", "showing", "late", "cues", "off"] {
            XCTAssertEqual(result?[key] as? Bool, true, key)
        }
    }

    func testNativeCaptionLanguageRequiresAMatch() {
        XCTAssertFalse(NativeCaptionPreference.matches("en", nativeTag: "ja"))
        XCTAssertFalse(NativeCaptionPreference.matches("en", nativeTag: ""))
        XCTAssertFalse(NativeCaptionPreference.matches("", nativeTag: "en"))
        XCTAssertTrue(NativeCaptionPreference.matches("en", nativeTag: "en-US"))
        XCTAssertTrue(NativeCaptionPreference.matches("EN_us", nativeTag: "en-US"))
    }

    func testUnknownAndMissingNativeCaptionsRejectHandoff() async throws {
        let item = AVPlayerItem(asset: AVMutableComposition())
        let preferences: [[String: Any]] = [["known": false], ["known": true, "enabled": true, "language": "en"]]
        for value in preferences {
            do {
                try await NativeCaptionPreference(value).apply(to: item)
                XCTFail("Unknown or unavailable captions must preserve website playback")
            } catch {
                guard case VideoError.noNativeCaptions = error else { return XCTFail("Unexpected error: \(error)") }
            }
        }
        try await NativeCaptionPreference(["known": true, "enabled": false]).apply(to: item)
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
