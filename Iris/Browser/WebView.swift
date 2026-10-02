import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    let model: BrowserModel
    let initialURL: URL
    let settings: SettingsStore

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
        context.coordinator.settings = settings
        context.coordinator.initialLoad = Task { [weak view] in
            guard let view else { return }
            await settings.blocker.register(view, settings: settings)
            guard !Task.isCancelled else { return }
            model.load(initialURL)
        }
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        let site = model.url?.host.map(PublicSuffix.bundled.registrableDomain) ?? ""
        view.configuration.preferences.javaScriptCanOpenWindowsAutomatically = model.allowedSites.contains(site)
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading()
        coordinator.initialLoad?.cancel()
        coordinator.settings?.blocker.unregister(view)
        view.navigationDelegate = nil
        view.uiDelegate = nil
        view.configuration.userContentController.removeScriptMessageHandler(forName: "irisGesture", contentWorld: .defaultClient)
        coordinator.observations.removeAll()
        coordinator.model.webView = nil
    }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let model: BrowserModel
        var observations: [NSKeyValueObservation] = []
        weak var settings: SettingsStore?
        var initialLoad: Task<Void, Never>?
        private var permittedStart = false
        private weak var permittedNavigation: WKNavigation?
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
            permittedNavigation = nil
            model.serverRedirectDestination = nil
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            model.error = error.localizedDescription
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url {
                if permitted(navigationAction, popup: true) { model.openWindow?(url) }
                else { block(url, popup: true) }
            }
            return nil
        }

        private func permitted(_ action: WKNavigationAction, popup: Bool = false) -> Bool {
            guard let url = action.request.url else { return false }
            return NavigationGuard(suffix: .bundled).allows(.init(
                destination: url, current: model.url,
                mainFrame: action.sourceFrame.isMainFrame, popup: popup,
                linkActivated: action.navigationType == .linkActivated,
                native: !popup && model.nativeDestination == url,
                historyOrReload: action.navigationType == .backForward || action.navigationType == .reload,
                form: action.navigationType == .formSubmitted || action.navigationType == .formResubmitted,
                serverRedirect: !popup && model.serverRedirectDestination == url,
                clickedLink: model.lastLink, gestureAge: Date().timeIntervalSince(model.lastGestureTime),
                allowedSites: model.allowedSites))
        }

        private func block(_ url: URL, popup: Bool) {
            model.blocked = BlockedNavigation(url: url,
                sourceSite: model.url?.host.map(PublicSuffix.bundled.registrableDomain) ?? "", popup: popup)
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            // Subframe loads stay in their frame. New windows are checked by WKUIDelegate.
            guard let target = action.targetFrame else { decisionHandler(.allow); return }
            guard target.isMainFrame else { decisionHandler(.allow); return }
            let allowed = permitted(action)
            if model.nativeDestination == action.request.url { model.nativeDestination = nil }
            if model.serverRedirectDestination == action.request.url { model.serverRedirectDestination = nil }
            if allowed {
                permittedStart = true
                model.blocked = nil
                // One gesture authorizes one destination, not later timers.
                model.lastLink = nil
                decisionHandler(.allow)
            } else {
                if let url = action.request.url { block(url, popup: false) }
                decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            permittedNavigation = permittedStart ? navigation : nil
            permittedStart = false
            model.lastLink = nil
        }

        func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
            if let navigation, navigation === permittedNavigation {
                model.serverRedirectDestination = webView.url
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            permittedNavigation = nil
            model.serverRedirectDestination = nil
            model.lastLink = nil
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
