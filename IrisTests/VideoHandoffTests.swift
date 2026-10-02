import XCTest
import AVFoundation
import WebKit
import UIKit
@testable import Iris

@MainActor final class VideoHandoffTests: XCTestCase {
    // Hold the final load/seek stage open while the window or document changes.
    func testPendingPlayerCannotPresentAfterNavigationClosureOrSourceChange() async throws {
        let (view, frame) = try await fixture()
        defer { view.stopLoading(); view.removeFromSuperview() }
        for change in 0..<3 {
            let model = BrowserModel()
            let coordinator = WebView.Coordinator(model: model)
            model.webView = view
            let candidate = VideoCandidate(descriptor: descriptor("https://example.com/a.mp4"), frame: frame)
            model.video = candidate
            let token = UUID()
            model.videoPreparationID = token
            model.isPreparingVideo = true
            var release: CheckedContinuation<AVPlayer, Never>?
            let task = Task {
                try await model.completeHandoff(token, candidate: candidate, view: view, pageURL: view.url,
                                                wasPlaying: true) {
                    await withCheckedContinuation { release = $0 }
                }
            }
            while release == nil { await Task.yield() }
            switch change {
            case 0: coordinator.webView(view, didStartProvisionalNavigation: nil)
            case 1: WebView.dismantleUIView(view, coordinator: coordinator)
            default:
                model.video = VideoCandidate(descriptor: descriptor("https://example.com/b.mp4"), frame: candidate.frame)
            }
            release?.resume(returning: AVPlayer())
            do { try await task.value; XCTFail("A stale video opened") }
            catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertNil(model.playerSession)
            if change < 2 { XCTAssertFalse(model.isPreparingVideo) }
        }
    }

    func testUnchangedPreparationPresentsAndClosedWindowCanDismiss() async throws {
        let model = BrowserModel()
        let (view, frame) = try await fixture()
        defer { view.stopLoading(); view.removeFromSuperview() }
        model.webView = view
        let candidate = VideoCandidate(descriptor: descriptor("https://example.com/a.mp4"), frame: frame)
        model.video = candidate
        let token = UUID()
        model.videoPreparationID = token
        let player = AVPlayer()
        try await model.completeHandoff(token, candidate: candidate, view: view, pageURL: view.url,
                                        wasPlaying: false) { await Task.yield(); return player }
        XCTAssertTrue(model.playerSession?.player === player)
        // Closing a window must not attempt to resume its website.
        model.webView = nil
        await model.closePlayer()
        XCTAssertNil(model.playerSession)
    }

    func testStalledPlaybackOffersFreshItemAndCloseCancelsRetry() async throws {
        let (view, frame) = try await fixture()
        defer { view.stopLoading(); view.removeFromSuperview() }
        let candidate = VideoCandidate(descriptor: descriptor("https://example.com/a.mp4"), frame: frame)
        let first = AVPlayerItem(url: URL(fileURLWithPath: "/nonexistent-first.mp4"))
        let replacement = AVPlayerItem(url: URL(fileURLWithPath: "/nonexistent-retry.mp4"))
        let player = AVPlayer(playerItem: first)
        let session = PlayerSession(player: player, candidate: candidate, wasPlaying: true, pageURL: view.url,
                                    retryItem: { replacement })
        NotificationCenter.default.post(name: AVPlayerItem.playbackStalledNotification, object: first)
        for _ in 0..<50 {
            if session.error != nil { break }
            await Task.yield()
        }
        XCTAssertNotNil(session.error)
        XCTAssertTrue(session.canRetry)
        session.retry()
        XCTAssertTrue(player.currentItem === replacement, "Retry must rebuild the item rather than reuse a failed item")
        session.stop()
        for _ in 0..<50 { await Task.yield() }
        XCTAssertFalse(session.isRetrying)
        XCTAssertEqual(player.rate, 0, "A closing player must not resume after its retry completes")
    }

    private final class FrameRecorder: NSObject, WKScriptMessageHandler {
        var frame: WKFrameInfo?
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            frame = message.frameInfo
        }
    }

    private func fixture() async throws -> (WKWebView, WKFrameInfo) {
        let recorder = FrameRecorder()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(recorder, name: "frame")
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = try XCTUnwrap(scene.windows.first)
        window.addSubview(view)
        view.loadHTMLString("<script>window.webkit.messageHandlers.frame.postMessage('ready')</script>",
                            baseURL: URL(string: "https://example.com"))
        for _ in 0..<450 {
            if recorder.frame != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        configuration.userContentController.removeScriptMessageHandler(forName: "frame")
        return (view, try XCTUnwrap(recorder.frame))
    }

    private func descriptor(_ source: String) -> VideoDescriptor {
        .init(id: "video", source: source, manifest: nil, time: 10, duration: 100,
              drm: false, nativeFullscreen: true)
    }
}
