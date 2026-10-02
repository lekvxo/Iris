import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    let model: BrowserModel
    let initialURL: URL

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.preferredContentMode = .desktop
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.userContentController.add(context.coordinator, contentWorld: .defaultClient, name: "irisGesture")
        configuration.userContentController.addUserScript(WKUserScript(
            source: ScriptSource.read("GestureProbe"), injectionTime: .atDocumentStart,
            forMainFrameOnly: true, in: .defaultClient))
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.allowsBackForwardNavigationGestures = true
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        model.webView = view
        context.coordinator.observe(view)
        model.load(initialURL)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading()
        view.navigationDelegate = nil
        view.uiDelegate = nil
        view.configuration.userContentController.removeScriptMessageHandler(forName: "irisGesture", contentWorld: .defaultClient)
        coordinator.observations.removeAll()
        coordinator.model.webView = nil
    }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let model: BrowserModel
        var observations: [NSKeyValueObservation] = []
        init(model: BrowserModel) { self.model = model }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "irisGesture", message.frameInfo.isMainFrame,
                  let body = message.body as? [String: Any] else { return }
            model.lastLink = (body["href"] as? String).flatMap(URL.init(string:))
            model.lastGestureTime = Date()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            report(error)
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            report(error)
        }
        private func report(_ error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            model.error = error.localizedDescription
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.navigationType == .linkActivated, navigationAction.sourceFrame.isMainFrame,
               let url = navigationAction.request.url {
                model.openWindow?(url)
            }
            return nil
        }

        func observe(_ view: WKWebView) {
            observations = [
                view.observe(\.url, options: [.new]) { [weak self] view, _ in
                    MainActor.assumeIsolated { self?.model.sync(from: view) }
                },
                view.observe(\.title, options: [.new]) { [weak self] view, _ in
                    MainActor.assumeIsolated { self?.model.sync(from: view) }
                },
                view.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
                    MainActor.assumeIsolated { self?.model.sync(from: view) }
                },
                view.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
                    MainActor.assumeIsolated { self?.model.sync(from: view) }
                },
                view.observe(\.canGoBack, options: [.new]) { [weak self] view, _ in
                    MainActor.assumeIsolated { self?.model.sync(from: view) }
                },
                view.observe(\.canGoForward, options: [.new]) { [weak self] view, _ in
                    MainActor.assumeIsolated { self?.model.sync(from: view) }
                }
            ]
        }
    }
}
