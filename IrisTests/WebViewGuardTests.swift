import XCTest
import WebKit
@testable import Iris

@MainActor final class WebViewGuardTests: XCTestCase {
    func testDelegateImplementsPolicySelector() {
        let coordinator = WebView.Coordinator(model: BrowserModel())
        XCTAssertTrue(coordinator.responds(to: NSSelectorFromString("webView:decidePolicyForNavigationAction:decisionHandler:")))
    }
}
