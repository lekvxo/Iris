import UIKit
import WebKit

// WebKit temporarily reparents its view during element fullscreen. Keep a stable SwiftUI host.
@MainActor final class BrowserWebContainer: UIView {
    let webView: WKWebView
    private weak var model: BrowserModel?
    private var webConstraints: [NSLayoutConstraint] = []

    init(webView: WKWebView, model: BrowserModel) {
        self.webView = webView
        self.model = model
        super.init(frame: .zero)
        addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webConstraints = [webView.topAnchor.constraint(equalTo: topAnchor),
                          webView.bottomAnchor.constraint(equalTo: bottomAnchor),
                          webView.leadingAnchor.constraint(equalTo: leadingAnchor),
                          webView.trailingAnchor.constraint(equalTo: trailingAnchor)]
        NSLayoutConstraint.activate(webConstraints)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        // Removing a view invalidates constraints to its former superview. Reinstall them on return.
        if webView.superview === self, webConstraints.contains(where: { !$0.isActive }) {
            NSLayoutConstraint.activate(webConstraints)
        }
        super.layoutSubviews()
        if let model, !model.isWebFullscreen, model.playerSession == nil, let window {
            model.browserScene = window.windowScene
            model.browserWindowSize = window.bounds.size
        }
    }
}

extension BrowserModel {
    func restoreBrowserWindow(reset: Bool = false) {
        guard let scene = browserScene else { return }
        let previous = reset ? CGSize(width: 1100, height: 760) : browserWindowSize
        let size = CGSize(width: max(900, previous.width), height: max(600, previous.height))
        let preferences = UIWindowScene.GeometryPreferences.Vision(
            size: size, minimumSize: CGSize(width: 900, height: 600),
            maximumSize: CGSize(width: UIProposedSceneSizeNoPreference, height: UIProposedSceneSizeNoPreference),
            resizingRestrictions: .freeform)
        scene.requestGeometryUpdate(preferences) { error in
            print("[Iris window] Could not restore browser size: \(error.localizedDescription)")
        }
        webView?.superview?.setNeedsLayout()
        webView?.scrollView.setNeedsLayout()
        webView?.evaluateJavaScript("window.dispatchEvent(new Event('resize'))", completionHandler: nil)
    }
}
