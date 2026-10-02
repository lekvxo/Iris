import XCTest
@testable import Iris

final class InputRouterTests: XCTestCase {
    func testDomains() {
        XCTAssertEqual(InputRouter.destination(for: "apple.com").absoluteString, "https://apple.com")
        XCTAssertEqual(InputRouter.destination(for: "news.ycombinator.com/item?id=1").absoluteString, "https://news.ycombinator.com/item?id=1")
        XCTAssertEqual(InputRouter.destination(for: "localhost:3000").absoluteString, "https://localhost:3000")
        XCTAssertEqual(InputRouter.destination(for: "http://apple.com/a").scheme, "http")
    }
    func testSearchEncoding() {
        for text in ["how to cook rice", "1+1", "a&b # c", "javascript:alert(1)", "bad..host"] {
            let url = InputRouter.destination(for: text)
            XCTAssertEqual(url.host, "www.google.com")
            XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, text)
        }
    }
}
