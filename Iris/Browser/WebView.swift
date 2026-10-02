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
        coordinator.observations.removeAll()
        coordinator.model.webView = nil
    }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let model: BrowserModel
        var observations: [NSKeyValueObservation] = []
        init(model: BrowserModel) { self.model = model }

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
