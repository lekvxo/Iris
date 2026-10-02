import Observation
import WebKit

@MainActor @Observable
final class BrowserModel {
    var url: URL?
    var title = "Iris"
    var canGoBack = false
    var canGoForward = false
    var isLoading = false
    var estimatedProgress = 0.0
    var error: String?
    @ObservationIgnored weak var webView: WKWebView?
    @ObservationIgnored var openWindow: ((URL) -> Void)?
    @ObservationIgnored var lastLink: URL?
    @ObservationIgnored var lastGestureTime = Date.distantPast
    @ObservationIgnored var nativeDestination: URL?
    @ObservationIgnored var serverRedirectDestination: URL?
    var blocked: BlockedNavigation?
    var allowedSites: Set<String> = []
    var video: VideoCandidate?
    var videoError: String?
    var isPreparingVideo = false

    func watchReason(native: Bool) -> String? {
        guard let video else { return "Play a video on the page to detect it" }
        if native { return video.descriptor.nativeFullscreen ? nil : "This video has no website fullscreen control" }
        if case .unsupported(let reason) = VideoBridge.classify(video.descriptor) { return reason }
        return nil
    }

    func load(_ url: URL) {
        error = nil
        nativeDestination = url
        webView?.load(URLRequest(url: url))
    }

    func sync(from view: WKWebView) {
        url = view.url
        title = view.title ?? "Iris"
        canGoBack = view.canGoBack
        canGoForward = view.canGoForward
        isLoading = view.isLoading
        estimatedProgress = view.estimatedProgress
    }
}
