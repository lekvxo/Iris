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
