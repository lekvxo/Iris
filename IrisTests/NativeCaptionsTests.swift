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
        configuration.userContentController.addUserScript(WKUserScript(source: ScriptSource.read("NativeCaptions"), injectionTime: .atDocumentStart, forMainFrameOnly: false))
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
                    noBridge: !v.querySelector('track') && v.textTracks.length === 2,
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

    func testPublicSelectedTrackTransfersLoadedCuesWithoutGuessingOrRequests() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(WKUserScript(source: ScriptSource.read("NativeCaptions"), injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = try XCTUnwrap(scene.windows.first)
        window.addSubview(view)
        defer { view.stopLoading(); view.removeFromSuperview() }
        view.loadHTMLString("<html><body><media-player id='p' data-media-player data-captions><video id='v'></video></media-player></body></html>", baseURL: URL(string: "https://caption.example"))
        for _ in 0..<450 {
            if let value = try? await view.evaluateJavaScript("!!document.getElementById('v') && typeof irisPrepareNativeCaptions === 'function'"), value as? Bool == true { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let result = try await view.evaluateJavaScript("""
            (() => {
                const p = document.getElementById('p'), v = document.getElementById('v');
                const first = v.addTextTrack('subtitles', 'English', 'en'), second = v.addTextTrack('subtitles', 'Japanese', 'ja');
                first.mode = second.mode = 'disabled';
                const en = Object.assign(new EventTarget(), {kind:'subtitles', label:'English', language:'en', mode:'showing', cues:[]});
                const ja = Object.assign(new EventTarget(), {kind:'subtitles', label:'Japanese', language:'ja', mode:'showing', cues:[new VTTCue(0,100,'Japanese fixture')]});
                // Vidstack/Maverick replaces Event.target with its controller instance.
                // composedPath() still contains the actual DOM dispatch element.
                const selected = track => {
                    const event = new CustomEvent('text-track-change', {detail:track});
                    Object.defineProperty(event, 'target', {get: () => ({el:p})});
                    return p.dispatchEvent(event);
                };
                selected(en);
                const inline = v.textTracks.length === 2 && irisNativeCaptionPreference(v).language === 'en';
                irisPrepareNativeCaptions(v); v.dispatchEvent(new Event('webkitbeginfullscreen'));
                const nativeEN = v.textTracks[2];
                const pending = nativeEN.mode === 'hidden' && nativeEN.cues.length === 0;
                const original = new VTTCue(0,100,'English fixture'); original.line = 98; original.snapToLines = false;
                en.cues.push(original); en.dispatchEvent(new Event('load'));
                const copied = nativeEN.mode === 'showing' && nativeEN.cues.length === 1 && nativeEN.cues[0] !== original &&
                    nativeEN.cues[0].text === original.text && nativeEN.cues[0].startTime === original.startTime &&
                    original.line === 98 && !original.snapToLines && first.mode === 'disabled' && second.mode === 'disabled';
                nativeEN.mode = 'disabled';
                en.cues.push(new VTTCue(100,200,'Later fixture')); en.dispatchEvent(new Event('add-cue'));
                const off = nativeEN.mode === 'disabled';
                selected(ja);
                const nativeJA = v.textTracks[3];
                const language = nativeEN.mode === 'disabled' && nativeJA.mode === 'showing' && nativeJA.cues[0].text === 'Japanese fixture';
                selected(null);
                const disabled = nativeJA.mode === 'disabled' && !irisNativeCaptionPreference(v).enabled;
                selected(en); v.dispatchEvent(new Event('webkitendfullscreen'));
                const restored = nativeEN.mode === 'disabled' && first.mode === 'disabled' && second.mode === 'disabled';
                const count = v.textTracks.length;
                irisPrepareNativeCaptions(v); v.dispatchEvent(new Event('webkitbeginfullscreen'));
                const reused = v.textTracks.length === count && nativeEN.mode === 'showing' && nativeEN.cues.length === 2;
                v.dispatchEvent(new Event('webkitendfullscreen'));
                en.dispatchEvent(new Event('load'));
                return {inline, pending, copied, off, language, disabled, restored, reused,
                    detached: nativeEN.mode === 'disabled', noRequests: !v.querySelector('track[src]') && !v.hasAttribute('src')};
            })()
            """) as? [String: Any]
        for key in ["inline", "pending", "copied", "off", "language", "disabled", "restored", "reused", "detached", "noRequests"] {
            XCTAssertEqual(result?[key] as? Bool, true, key)
        }
    }

    func testEmbedFullscreenRequestUsesVideoAndFallsBackOnFailure() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(WKUserScript(source: ScriptSource.read("NativeCaptions"), injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = try XCTUnwrap(scene.windows.first)
        window.addSubview(view)
        defer { view.stopLoading(); view.removeFromSuperview() }
        view.loadHTMLString("<media-player id='p' data-media-player><video id='v'></video><button id='f'>Fullscreen</button></media-player>", baseURL: URL(string: "https://strm.cx"))
        for _ in 0..<450 {
            if let value = try? await view.evaluateJavaScript("!!document.getElementById('f') && typeof irisPrepareNativeCaptions === 'function'"), value as? Bool == true { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let result = try await view.callAsyncJavaScript("""
            const v = document.getElementById('v'), p = document.getElementById('p'), f = document.getElementById('f');
            let calls = 0, websiteCalls = 0;
            p.addEventListener('media-enter-fullscreen-request', () => websiteCalls++);
            Object.defineProperty(v, 'readyState', {configurable:true, value:4});
            v.webkitEnterFullscreen = () => { calls++; };
            const request = () => {
                const event = new CustomEvent('media-enter-fullscreen-request', {bubbles:true, cancelable:true});
                Object.defineProperty(event, 'target', {get: () => ({el:f})});
                return f.dispatchEvent(event);
            };
            const activation = navigator.userActivation.isActive;
            request();
            const direct = calls === 1 && websiteCalls === 0;
            irisRestoreNativeCaptions(v);
            v.webkitEnterFullscreen = () => { throw new Error('Fixture rejection'); };
            request();
            const fallback = websiteCalls === 1;
            v.webkitEnterFullscreen = () => { calls++; };
            const extra = document.createElement('video'); p.append(extra);
            request();
            const ambiguous = calls === 1 && websiteCalls === 2;
            extra.remove();
            Object.defineProperty(v, 'readyState', {configurable:true, value:0});
            request();
            return {activation, direct, fallback, ambiguous, unloaded: calls === 1 && websiteCalls === 3};
            """, arguments: [:], in: nil, contentWorld: .page) as? [String: Any]
        for key in ["activation", "direct", "fallback", "ambiguous", "unloaded"] {
            XCTAssertEqual(result?[key] as? Bool, true, key)
        }
    }

    func testUnenteredFullscreenCleansUpCopiedCaptions() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(WKUserScript(source: ScriptSource.read("NativeCaptions"), injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.loadHTMLString("<media-player id='p' data-media-player><video id='v'></video></media-player>", baseURL: URL(string: "https://caption.example"))
        for _ in 0..<450 {
            if let value = try? await view.evaluateJavaScript("!!document.getElementById('v') && typeof irisPrepareNativeCaptions === 'function'"), value as? Bool == true { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let result = try await view.callAsyncJavaScript("""
            const v = document.getElementById('v'), p = document.getElementById('p');
            const selected = Object.assign(new EventTarget(), {kind:'subtitles', label:'English', language:'en', mode:'showing', cues:[new VTTCue(0,100,'Fixture')]});
            p.dispatchEvent(new CustomEvent('text-track-change', {detail:selected}));
            irisPrepareNativeCaptions(v);
            const prepared = v.textTracks[0].mode === 'showing';
            await new Promise(resolve => setTimeout(resolve, 5200));
            return prepared && v.textTracks[0].mode === 'disabled';
            """, arguments: [:], in: nil, contentWorld: .page)
        XCTAssertEqual(result as? Bool, true)
    }

    func testFullscreenSelectionResetRestoresOnceAndPreservesNativeOff() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(WKUserScript(source: ScriptSource.read("NativeCaptions"), injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.loadHTMLString("<media-player id='p' data-media-player><video id='v'></video></media-player>", baseURL: URL(string: "https://caption.example"))
        for _ in 0..<450 {
            if let value = try? await view.evaluateJavaScript("!!document.getElementById('v') && typeof irisPrepareNativeCaptions === 'function'"), value as? Bool == true { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let result = try await view.callAsyncJavaScript("""
            const p = document.getElementById('p'), v = document.getElementById('v');
            const track = Object.assign(new EventTarget(), {kind:'subtitles', label:'English', language:'en', mode:'showing', cues:[new VTTCue(0,100,'Fixture')]});
            p.dispatchEvent(new CustomEvent('text-track-change', {detail:track}));
            irisPrepareNativeCaptions(v);
            const native = v.textTracks[0], prepared = native.mode === 'showing';
            // Reproduce the actual headset: transition disables the prepared track.
            v.dispatchEvent(new Event('webkitbeginfullscreen'));
            native.mode = 'disabled';
            await new Promise(resolve => setTimeout(resolve, 25));
            const restored = native.mode === 'showing' && native.cues.length === 1;
            // A later native Off choice and duplicate transition event stay Off.
            native.mode = 'disabled';
            v.dispatchEvent(new Event('webkitbeginfullscreen'));
            track.dispatchEvent(new Event('load'));
            await new Promise(resolve => setTimeout(resolve, 25));
            const off = native.mode === 'disabled';
            irisRestoreNativeCaptions(v);
            // Exiting immediately must cancel pending activation.
            irisPrepareNativeCaptions(v);
            v.dispatchEvent(new Event('webkitbeginfullscreen'));
            irisRestoreNativeCaptions(v);
            await new Promise(resolve => setTimeout(resolve, 25));
            return {prepared, restored, off, cancelled: native.mode === 'disabled'};
            """, arguments: [:], in: nil, contentWorld: .page) as? [String: Any]
        for key in ["prepared", "restored", "off", "cancelled"] {
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
