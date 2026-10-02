import XCTest
import WebKit
@testable import Iris

@MainActor final class WindowLifetimeTests: XCTestCase {
    private final class References {
        weak var view: WKWebView?
        weak var model: BrowserModel?
        weak var coordinator: WebView.Coordinator?
    }
    func testFourWindowWebViewsReleaseAfterDismantling() {
        var windows: [(WKWebView, BrowserModel, WebView.Coordinator)] = []
        var references: [References] = []
        for _ in 0..<4 {
            let model = BrowserModel()
            let coordinator = WebView.Coordinator(model: model)
            let view = WKWebView()
            model.webView = view
            coordinator.observe(view)
            view.navigationDelegate = coordinator
            view.uiDelegate = coordinator
            view.configuration.userContentController.add(coordinator, contentWorld: .defaultClient, name: "irisGesture")
            view.configuration.userContentController.add(coordinator, name: "irisVideo")
            let reference = References()
            reference.view = view
            reference.model = model
            reference.coordinator = coordinator
            references.append(reference)
            windows.append((view, model, coordinator))
        }
        for (view, model, coordinator) in windows {
            WebView.dismantleUIView(view, coordinator: coordinator)
            XCTAssertNil(model.webView)
            XCTAssertTrue(coordinator.observations.isEmpty)
        }
        windows.removeAll()
        for reference in references {
            XCTAssertNil(reference.view)
            XCTAssertNil(reference.model)
            XCTAssertNil(reference.coordinator)
        }
    }
}
