import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    let model: BrowserModel
    let initialURL: URL
    let settings: SettingsStore
    let probeInterval: Int

    func makeCoordinator() -> Coordinator { model.popup?.coordinator ?? Coordinator(model: model) }

    func makeUIView(context: Context) -> WKWebView {
        // A popup arrives already loading, wired to this coordinator by its opener.
        if let popup = model.popup {
            model.popup = nil
            return popup.view
        }
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.preferredContentMode = .desktop
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let view = Self.makeWebView(configuration, coordinator: context.coordinator, settings: settings)
        context.coordinator.initialLoad = Task { [weak view, weak model] in
            await settings.blocker.prepare(settings: settings)
            guard !Task.isCancelled, let view, let model else { return }
            settings.blocker.register(view, settings: settings)
            model.isInitializing = false
            model.load(initialURL)
        }
        return view
    }

    static func makeWebView(_ configuration: WKWebViewConfiguration, coordinator: Coordinator, settings: SettingsStore) -> WKWebView {
        // Each window gets its own controller so script messages reach its own coordinator.
        // A popup's configuration arrives holding its opener's controller, so it is always replaced.
        let controller = WKUserContentController()
        controller.add(coordinator, name: "irisPopup")
        controller.addUserScript(WKUserScript(
            source: ScriptSource.read("PopupProbe"), injectionTime: .atDocumentStart, forMainFrameOnly: false))
        controller.add(coordinator, contentWorld: .defaultClient, name: "irisGesture")
        controller.addUserScript(WKUserScript(
            source: ScriptSource.read("GestureProbe"), injectionTime: .atDocumentStart,
            forMainFrameOnly: true, in: .defaultClient))
        controller.add(coordinator, name: "irisVideo")
        controller.addUserScript(WKUserScript(
            source: ScriptSource.read("VideoProbe"), injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        configuration.userContentController = controller
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.allowsBackForwardNavigationGestures = true
        view.navigationDelegate = coordinator
        view.uiDelegate = coordinator
        coordinator.model.webView = view
        coordinator.observe(view)
        coordinator.settings = settings
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        let site = model.url?.host.map(PublicSuffix.bundled.registrableDomain) ?? ""
        view.configuration.preferences.javaScriptCanOpenWindowsAutomatically = model.allowedSites.contains(site)
        context.coordinator.updateVideoPolicy(view, interval: probeInterval)
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading()
        coordinator.initialLoad?.cancel()
        coordinator.initialLoad = nil
        coordinator.settings?.blocker.unregister(view)
        view.navigationDelegate = nil
        view.uiDelegate = nil
        view.configuration.userContentController.removeScriptMessageHandler(forName: "irisGesture", contentWorld: .defaultClient)
        view.configuration.userContentController.removeScriptMessageHandler(forName: "irisVideo")
        view.configuration.userContentController.removeScriptMessageHandler(forName: "irisPopup")
        coordinator.observations.removeAll()
        coordinator.model.webView = nil
        coordinator.model.invalidateVideo()
        coordinator.model.video = nil
        coordinator.model.openWindow = nil
        coordinator.model.closeWindow = nil
    }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let model: BrowserModel
        var observations: [NSKeyValueObservation] = []
        weak var settings: SettingsStore?
        var initialLoad: Task<Void, Never>?
        private var videoPolicy: String?
        private var permittedStart = false
        private weak var permittedNavigation: WKNavigation?
        init(model: BrowserModel) { self.model = model }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "irisPopup", let body = message.body as? [String: Any],
               let value = body["url"] as? String, let url = URL(string: value),
               ["http", "https"].contains(url.scheme), url.host != nil {
                // Same rule as createWebViewWith, so an allowed sign-in popup shows no chip.
                let allowed = NavigationGuard(suffix: .bundled).allows(.init(
                    destination: url, current: model.url, mainFrame: message.frameInfo.isMainFrame, popup: true,
                    gestureAge: Date().timeIntervalSince(model.lastGestureTime), allowedSites: model.allowedSites))
                if !allowed { block(url, popup: true) }
                return
            }
            if message.name == "irisVideo", let body = message.body as? [String: Any],
               let id = body["id"] as? String, let src = body["src"] as? String {
                let video = VideoDescriptor(id: id, source: src, manifest: body["manifest"] as? String,
                    time: body["time"] as? Double ?? 0, duration: body["duration"] as? Double,
                    drm: body["drm"] as? Bool ?? false, nativeFullscreen: body["nativeFullscreen"] as? Bool ?? false,
                    isPlaying: body["playing"] as? Bool ?? false)
                if VideoBridge.shouldReplace(model.video?.descriptor, with: video) {
                    model.video = VideoCandidate(descriptor: video, frame: message.frameInfo)
                }
                return
            }
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
            let error = error as NSError
            guard error.code != NSURLErrorCancelled else { return }
            // 102 is WebKit's "frame load interrupted", sent when a link is a download.
            guard !(error.domain == "WebKitErrorDomain" && error.code == 102) else { return }
            // Try again should retry the page that failed, not the last typed address.
            if let failed = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL { model.requestedURL = failed }
            model.error = error.localizedDescription
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            guard let url = navigationAction.request.url else { return nil }
            guard permitted(navigationAction, popup: true) else { block(url, popup: true); return nil }
            guard let settings, let openWindow = model.openWindow else { return nil }
            // Return a real web view so the page keeps window.opener; sign-in popups report back through it.
            let popup = BrowserModel()
            let coordinator = Coordinator(model: popup)
            let view = WebView.makeWebView(configuration, coordinator: coordinator, settings: settings)
            popup.isInitializing = false
            popup.requestedURL = url
            // The guard already approved this request; treat it like an address-bar load in the popup.
            popup.nativeDestination = url
            popup.popup = (view, coordinator)
            settings.blocker.register(view, settings: settings)
            let request = WindowRequest(url: url)
            BrowserModel.pendingPopups[request.id] = popup
            openWindow(request)
            return view
        }

        func webViewDidClose(_ webView: WKWebView) {
            model.closeWindow?()
        }

        private func permitted(_ action: WKNavigationAction, popup: Bool = false) -> Bool {
            guard let url = action.request.url else { return false }
            if !popup, action.sourceFrame.isMainFrame, let archive = model.nativeArchiveDestination,
               url == archive || url.absoluteString == "about:blank" { return true }
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
            model.nativeArchiveDestination = nil
            if model.nativeDestination == action.request.url { model.nativeDestination = nil }
            if model.serverRedirectDestination == action.request.url { model.serverRedirectDestination = nil }
            if allowed {
                settings?.blocker.apply(to: webView, destination: action.request.url)
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
            model.invalidateVideo()
            model.error = nil
            model.video = nil
            model.videoError = nil
            permittedNavigation = permittedStart ? navigation : nil
            permittedStart = false
            model.lastLink = nil
        }

        func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
            if let navigation, navigation === permittedNavigation {
                model.serverRedirectDestination = webView.url
                settings?.blocker.apply(to: webView, destination: webView.url)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            permittedNavigation = nil
            model.serverRedirectDestination = nil
            model.lastLink = nil
            videoPolicy = nil
            updateVideoPolicy(webView)
        }

        func updateVideoPolicy(_ view: WKWebView, interval: Int? = nil) {
            let enabled = !model.isBackgrounded && model.playerSession == nil
            let interval = interval ?? settings?.energy.probeInterval ?? 250
            let policy = "{type:'iris-video-policy',enabled:\(enabled),interval:\(interval)}"
            guard videoPolicy != policy else { return }
            videoPolicy = policy
            view.evaluateJavaScript("window.postMessage(\(policy), '*')", completionHandler: nil)
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
