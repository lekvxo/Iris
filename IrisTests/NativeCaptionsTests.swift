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

    // Mirrors the observed React DOM: no public player.textTracks/controls API.
    // WebKit parses a real VTT resource; fullscreen/Moon rendering still needs a headset.
    func testReactCaptionsLoadIndependentNativeTrackAndRespectOff() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(WKUserScript(source: ScriptSource.read("NativeCaptions"), injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = try XCTUnwrap(scene.windows.first)
        window.addSubview(view)
        defer { view.stopLoading(); view.removeFromSuperview() }
        view.loadHTMLString("<html><body><media-player id='p' data-media-player data-captions><video id='v'></video></media-player></body></html>", baseURL: URL(string: "https://caption.example"))
        var ready = false
        for _ in 0..<450 {
            if let value = try? await view.evaluateJavaScript("typeof window.irisPrepareNativeCaptions === 'function'"), value as? Bool == true { ready = true; break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(ready)
        let result = try await view.callAsyncJavaScript(#"""
            const p = document.getElementById('p'), v = document.getElementById('v');
            const original = document.createElement('track');
            original.kind = 'subtitles'; original.label = 'English'; original.srclang = 'en';
            const url = URL.createObjectURL(new Blob(['WEBVTT\n\n00:00:00.000 --> 00:01:00.000\nFixture caption\n'], {type: 'text/vtt'}));
            original.src = url; v.append(original); original.track.mode = 'disabled';
            // The library owns and repeatedly disables its track, not our separate one.
            v.textTracks.onchange = () => { original.track.mode = 'disabled'; };
            const selected = window.irisNativeCaptionPreference(v);
            window.irisPrepareNativeCaptions(v);
            v.dispatchEvent(new Event('webkitbeginfullscreen'));
            const bridge = v.querySelector('[data-iris-caption]');
            for (let i = 0; i < 100 && (bridge.readyState !== 2 || bridge.track.mode !== 'showing'); i++) await new Promise(r => setTimeout(r, 20));
            const loaded = bridge.readyState === 2 && bridge.track.cues?.length === 1 && bridge.track.cues[0].text === 'Fixture caption';
            const native = bridge.track.mode === 'showing' && original.track.mode === 'disabled';
            Object.defineProperty(v, 'webkitPresentationMode', {configurable: true, value: 'picture-in-picture'});
            v.dispatchEvent(new Event('webkitendfullscreen'));
            document.dispatchEvent(new Event('fullscreenchange'));
            const retained = v.querySelector('[data-iris-caption]') === bridge;
            Object.defineProperty(v, 'webkitPresentationMode', {configurable: true, value: 'inline'});
            const unchanged = p.controls === undefined && p.textTracks === undefined && !v.hasAttribute('controls') && !v.hasAttribute('src');
            bridge.track.mode = 'disabled'; v.textTracks.dispatchEvent(new Event('change'));
            p.setAttribute('data-playing', '');
            await new Promise(r => setTimeout(r, 20));
            const off = bridge.track.mode === 'disabled';
            v.dispatchEvent(new Event('webkitendfullscreen'));
            const restored = !v.querySelector('[data-iris-caption]') && original.isConnected && original.track.mode === 'disabled';
            // A website caption-off selection must stay off on the next entry.
            p.removeAttribute('data-captions'); window.irisPrepareNativeCaptions(v);
            const websiteOff = !v.querySelector('[data-iris-caption]') && !window.irisNativeCaptionPreference(v).enabled;
            v.dispatchEvent(new Event('fullscreenerror', {bubbles: true}));
            p.setAttribute('data-captions', '');
            // Multiple files do not identify the selected language: do not guess from default.
            const second = original.cloneNode(); second.srclang = 'ja'; v.append(second);
            const ambiguous = !window.irisNativeCaptionPreference(v).known;
            window.irisPrepareNativeCaptions(v);
            const untouched = !v.querySelector('[data-iris-caption]');
            window.irisRestoreNativeCaptions(v); second.remove();
            // A later track/source update and website Off are observed during fullscreen.
            window.irisPrepareNativeCaptions(v); v.dispatchEvent(new Event('webkitbeginfullscreen'));
            original.src = url + '#new';
            await new Promise(r => setTimeout(r, 20));
            const changed = v.querySelector('[data-iris-caption]')?.src === original.src;
            p.removeAttribute('data-captions');
            await new Promise(r => setTimeout(r, 20));
            const websiteExit = !v.querySelector('[data-iris-caption]');
            v.dispatchEvent(new Event('webkitendfullscreen'));
            v.textTracks.onchange = null;
            p.setAttribute('data-captions', ''); original.track.mode = 'showing';
            window.irisPrepareNativeCaptions(v);
            const existingNative = !v.querySelector('[data-iris-caption]') && original.track.mode === 'showing';
            v.dispatchEvent(new Event('webkitendfullscreen'));
            URL.revokeObjectURL(url);
            return {selected: selected.known && selected.enabled && selected.language === 'en', loaded, native, retained, unchanged,
                off, restored, websiteOff, ambiguous, untouched, changed, websiteExit, existingNative};
            """#, arguments: [:], in: nil, contentWorld: .page) as? [String: Any]
        for key in ["selected", "loaded", "native", "retained", "unchanged", "off", "restored", "websiteOff", "ambiguous", "untouched", "changed", "websiteExit", "existingNative"] {
            XCTAssertEqual(result?[key] as? Bool, true, key)
        }
    }

    func testOnlySingleVideoPlayerWrapperUsesNativeFullscreenAndFailureCleansUp() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(WKUserScript(source: ScriptSource.read("NativeCaptions"), injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.loadHTMLString("""
            <html><body><media-player id='p' data-media-player data-captions><video id='v'><track kind='subtitles' src='data:text/vtt,WEBVTT' srclang='en'></video></media-player><div id='other'></div>
            <script>
            window.nativeCalls = 0; window.wrapperCalls = 0;
            HTMLVideoElement.prototype.webkitEnterFullscreen = function() { nativeCalls++; if(window.failEntry) throw new Error('Denied'); };
            Element.prototype.requestFullscreen = function() { wrapperCalls++; return Promise.resolve(); };
            </script></body></html>
            """, baseURL: URL(string: "https://caption.example"))
        for _ in 0..<450 {
            if let value = try? await view.evaluateJavaScript("typeof window.irisPrepareNativeCaptions === 'function'"), value as? Bool == true { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let result = try await view.callAsyncJavaScript("""
            const p = document.getElementById('p'), v = document.getElementById('v');
            await p.requestFullscreen();
            const routed = nativeCalls === 1 && wrapperCalls === 0 && !!v.querySelector('[data-iris-caption]');
            v.dispatchEvent(new Event('webkitendfullscreen'));
            window.failEntry = true;
            let rejected = false;
            try { await p.requestFullscreen(); } catch { rejected = true; }
            const cleaned = !v.querySelector('[data-iris-caption]');
            await document.getElementById('other').requestFullscreen();
            p.append(document.createElement('video')); await p.requestFullscreen();
            return {routed, rejected, cleaned, isolated: nativeCalls === 2 && wrapperCalls === 2};
            """, arguments: [:], in: nil, contentWorld: .page) as? [String: Any]
        for key in ["routed", "rejected", "cleaned", "isolated"] { XCTAssertEqual(result?[key] as? Bool, true, key) }
        view.stopLoading()
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
