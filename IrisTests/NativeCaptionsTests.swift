import XCTest
import WebKit
import UIKit
import AVFoundation
@testable import Iris

@MainActor final class NativeCaptionsTests: XCTestCase {
    func testNativeCaptionsPreserveWebsiteCuesAndRespectCaptionOff() async throws {
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
                track.addCue(cue); track.mode = 'hidden';
                const preference = window.irisNativeCaptionPreference(v);
                window.irisPrepareNativeCaptions(v);
                const unchanged = cue.line === 98 && !cue.snapToLines && cue.position === 90 && cue.size === 65 && cue.text === 'Visible caption' && cue.startTime === 0 && cue.endTime === 100;
                const promoted = track.mode === 'showing';
                v.dispatchEvent(new Event('webkitendfullscreen'));
                const restored = cue.line === 98 && !cue.snapToLines && cue.position === 90 && cue.size === 65;
                window.irisPrepareNativeCaptions(v);
                track.mode = 'disabled';
                v.dispatchEvent(new Event('webkitendfullscreen'));
                return {unchanged, promoted, restored, off: track.mode === 'disabled', language: preference.language, enabled: preference.enabled};
            })()
            """) as? [String: Any]
        XCTAssertEqual(result?["unchanged"] as? Bool, true)
        XCTAssertEqual(result?["promoted"] as? Bool, true)
        XCTAssertEqual(result?["restored"] as? Bool, true)
        XCTAssertEqual(result?["off"] as? Bool, true)
        XCTAssertEqual(result?["enabled"] as? Bool, true)
        XCTAssertEqual(result?["language"] as? String, "en")
        let disabled = try await view.evaluateJavaScript("window.irisNativeCaptionPreference(document.getElementById('v')).enabled")
        XCTAssertEqual(disabled as? Bool, false, "A disabled track must not be switched on")
    }

    // Synthetic fullscreen events exercise the WK script lifecycle, not headset rendering.
    func testCaptionGapsLateTracksWrapperFullscreenAndSelectionChanges() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(WKUserScript(source: ScriptSource.read("NativeCaptions"), injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = try XCTUnwrap(scene.windows.first)
        window.addSubview(view)
        defer { view.stopLoading(); view.removeFromSuperview() }
        view.loadHTMLString("<html><body><div id='wrapper'><video id='v'></video></div></body></html>", baseURL: URL(string: "https://caption.example"))
        var ready = false
        for _ in 0..<450 {
            if let value = try? await view.evaluateJavaScript("typeof window.irisPrepareNativeCaptions === 'function'"), value as? Bool == true { ready = true; break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(ready)
        let result = try await view.callAsyncJavaScript("""
            const v = document.getElementById('v');
            // Prepare with no track, then enter a standard fullscreen wrapper.
            window.irisPrepareNativeCaptions(v);
            Object.defineProperty(document, 'fullscreenElement', {configurable: true, value: document.getElementById('wrapper')});
            document.dispatchEvent(new Event('fullscreenchange'));
            const en = v.addTextTrack('subtitles', 'English', 'en');
            en.mode = 'hidden';
            const gap = window.irisNativeCaptionPreference(v);
            await new Promise(resolve => setTimeout(resolve, 20));
            v.textTracks.dispatchEvent(new Event('addtrack'));
            const lateTrack = en.mode === 'showing';
            const cue = new VTTCue(200, 201, 'Later caption');
            cue.line = 95; cue.snapToLines = false; cue.position = 80; cue.size = 60;
            en.addCue(cue); en.dispatchEvent(new Event('cuechange'));
            const lateCue = en.mode === 'showing' && cue.line === 95 && cue.position === 80 && cue.size === 60 && !cue.snapToLines;
            en.mode = 'disabled';
            v.textTracks.dispatchEvent(new Event('change'));
            en.dispatchEvent(new Event('cuechange'));
            const off = en.mode === 'disabled' && !window.irisNativeCaptionPreference(v).enabled;
            const ja = v.addTextTrack('subtitles', 'Japanese', 'ja');
            ja.mode = 'hidden';
            v.textTracks.dispatchEvent(new Event('change'));
            const language = ja.mode === 'showing' && window.irisNativeCaptionPreference(v).language === 'ja';
            // A site demoting the owned track must not be fought on every cue event.
            ja.mode = 'hidden'; v.textTracks.dispatchEvent(new Event('change'));
            ja.dispatchEvent(new Event('cuechange'));
            const released = ja.mode === 'hidden';
            Object.defineProperty(document, 'fullscreenElement', {configurable: true, value: null});
            document.dispatchEvent(new Event('fullscreenchange'));
            en.mode = 'hidden'; ja.mode = 'disabled';
            en.dispatchEvent(new Event('cuechange'));
            v.textTracks.dispatchEvent(new Event('change'));
            const detached = en.mode === 'hidden';
            ja.mode = 'hidden';
            const ambiguous = window.irisNativeCaptionPreference(v);
            window.irisPrepareNativeCaptions(v);
            const untouched = en.mode === 'hidden' && ja.mode === 'hidden';
            v.dispatchEvent(new Event('webkitendfullscreen'));
            return {gap: gap.enabled && gap.known && gap.language === 'en', lateTrack, lateCue, off, language, released, detached,
                    ambiguous: !ambiguous.known && !ambiguous.enabled, untouched};
            """, arguments: [:], in: nil, contentWorld: .page) as? [String: Any]
        for key in ["gap", "lateTrack", "lateCue", "off", "language", "released", "detached", "ambiguous", "untouched"] {
            XCTAssertEqual(result?[key] as? Bool, true, key)
        }
    }

    // This fixture models Vidstack's documented controls/textTracks contract.
    // It proves integration and restoration, not the library or Moon renderer itself.
    func testCustomPlayerNativeRendererOwnsSelectionAndRestoresControls() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(WKUserScript(source: ScriptSource.read("NativeCaptions"), injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = try XCTUnwrap(scene.windows.first)
        window.addSubview(view)
        defer { view.stopLoading(); view.removeFromSuperview() }
        view.loadHTMLString("<html><body><media-player id='p'><video id='v'></video></media-player></body></html>", baseURL: URL(string: "https://caption.example"))
        var ready = false
        for _ in 0..<450 {
            if let value = try? await view.evaluateJavaScript("typeof window.irisPrepareNativeCaptions === 'function'"), value as? Bool == true { ready = true; break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(ready)
        let result = try await view.evaluateJavaScript("""
            (() => {
                const p = document.getElementById('p'), v = document.getElementById('v');
                const nativeEN = v.addTextTrack('subtitles', 'English', 'en');
                const nativeJA = v.addTextTrack('subtitles', 'Japanese', 'ja');
                const cue = new VTTCue(100, 102, 'Website cue');
                cue.line = 98; cue.snapToLines = false; nativeEN.addCue(cue);
                const en = {kind: 'subtitles', language: 'en', mode: 'showing'};
                const ja = {kind: 'subtitles', language: 'ja', mode: 'disabled'};
                const tracks = new EventTarget();
                const items = [en];
                tracks[Symbol.iterator] = () => items[Symbol.iterator]();
                Object.defineProperty(p, 'textTracks', {value: tracks});
                let controls = false;
                const render = () => {
                    nativeEN.mode = controls && en.mode === 'showing' ? 'showing' : 'disabled';
                    nativeJA.mode = controls && ja.mode === 'showing' ? 'showing' : 'disabled';
                };
                Object.defineProperty(p, 'controls', {get: () => controls, set: value => {controls = value; render();}});
                tracks.addEventListener('add', render); tracks.addEventListener('mode-change', render);
                render();
                const selected = window.irisNativeCaptionPreference(v);
                const website = selected.enabled && selected.language === 'en' && nativeEN.mode === 'disabled';
                window.irisPrepareNativeCaptions(v);
                v.dispatchEvent(new Event('webkitbeginfullscreen'));
                const native = controls && nativeEN.mode === 'showing';
                // Late selection is rendered by the public player, not Iris track enforcement.
                items.push(ja); tracks.dispatchEvent(new Event('add'));
                en.mode = 'disabled'; ja.mode = 'showing'; tracks.dispatchEvent(new Event('mode-change'));
                const language = nativeEN.mode === 'disabled' && nativeJA.mode === 'showing' && window.irisNativeCaptionPreference(v).language === 'ja';
                en.mode = 'disabled'; ja.mode = 'disabled'; tracks.dispatchEvent(new Event('mode-change'));
                nativeJA.dispatchEvent(new Event('cuechange')); v.textTracks.dispatchEvent(new Event('change'));
                const off = !window.irisNativeCaptionPreference(v).enabled && nativeJA.mode === 'disabled';
                v.dispatchEvent(new Event('webkitendfullscreen'));
                const restored = !controls && en.mode === 'disabled' && ja.mode === 'disabled';
                en.mode = 'showing'; tracks.dispatchEvent(new Event('mode-change'));
                window.irisPrepareNativeCaptions(v);
                v.dispatchEvent(new Event('fullscreenerror', {bubbles: true}));
                const failed = !controls && nativeEN.mode === 'disabled' && en.mode === 'showing';
                // A page-owned controls change is not overwritten on exit.
                window.irisPrepareNativeCaptions(v); p.controls = false;
                v.dispatchEvent(new Event('webkitendfullscreen'));
                const ownership = !controls;
                window.irisPrepareNativeCaptions(v); window.dispatchEvent(new Event('pagehide'));
                const navigation = !controls;
                return {website, native, language, off, restored, failed, ownership, navigation,
                    cues: cue.line === 98 && !cue.snapToLines && cue.text === 'Website cue' && cue.startTime === 100 && cue.endTime === 102};
            })()
            """) as? [String: Any]
        for key in ["website", "native", "language", "off", "restored", "failed", "ownership", "navigation", "cues"] {
            XCTAssertEqual(result?[key] as? Bool, true, key)
        }
        let noBegin = try await view.callAsyncJavaScript("""
            const p = document.getElementById('p'), v = document.getElementById('v');
            window.irisPrepareNativeCaptions(v);
            await new Promise(resolve => setTimeout(resolve, 5100));
            return p.controls === false;
            """, arguments: [:], in: nil, contentWorld: .page)
        XCTAssertEqual(noBegin as? Bool, true, "A request without a fullscreen begin event must restore controls")
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
