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

    func load(_ url: URL) {
        error = nil
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
