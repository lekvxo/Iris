import XCTest
import WebKit
import UIKit
@testable import Iris

@MainActor final class WebViewGuardTests: XCTestCase {
    func testDelegateImplementsPolicySelector() {
        let coordinator = WebView.Coordinator(model: BrowserModel())
        XCTAssertTrue(coordinator.responds(to: NSSelectorFromString("webView:decidePolicyForNavigationAction:decisionHandler:")))
    }

    func testScriptedPopupAndCrossSiteJumpAreReportedAndDenied() async throws {
        let model = BrowserModel()
        let coordinator = WebView.Coordinator(model: model)
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.userContentController.add(coordinator, contentWorld: .defaultClient, name: "irisGesture")
        configuration.userContentController.addUserScript(WKUserScript(source: ScriptSource.read("GestureProbe"), injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .defaultClient))
        configuration.userContentController.add(coordinator, name: "irisPopup")
        configuration.userContentController.addUserScript(WKUserScript(source: ScriptSource.read("PopupProbe"), injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        host.view = view
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; WebView.dismantleUIView(view, coordinator: coordinator) }
        model.webView = view
        model.url = URL(string: "https://source.example.com")!
        model.nativeArchiveDestination = model.url
        view.navigationDelegate = coordinator
        view.uiDelegate = coordinator
        view.loadHTMLString("<html><body id='fixture'>Guard fixture</body></html>", baseURL: model.url)
        for _ in 0..<150 {
            if !view.isLoading, let exists = try? await view.evaluateJavaScript("!!document.getElementById('fixture')"), (exists as? Bool) == true { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let gesture = try await view.evaluateJavaScript("typeof window.webkit.messageHandlers.irisGesture") as? String
        XCTAssertEqual(gesture, "undefined", "Page world must not forge gesture messages")
        _ = try await view.evaluateJavaScript("window.open('https://popup.example.net'); null")
        for _ in 0..<50 {
            if model.blocked != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(model.blocked?.url.host, "popup.example.net")
        XCTAssertTrue(model.blocked?.popup == true)
        model.blocked = nil
        _ = try await view.evaluateJavaScript("location.href = 'https://jump.example.net'; null")
        for _ in 0..<50 {
            if model.blocked != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(model.blocked?.url.host, "jump.example.net")
        XCTAssertFalse(model.blocked?.popup ?? true)
        XCTAssertNotEqual(view.url?.host, "jump.example.net")
    }
}
