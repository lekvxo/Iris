import XCTest
@testable import Iris

final class NavigationGuardTests: XCTestCase {
    private let guardPolicy = NavigationGuard(suffix: .bundled)
    private let source = URL(string: "https://news.bbc.co.uk/article")!

    func testSameSiteAndHistory() {
        XCTAssertTrue(guardPolicy.allows(.init(destination: URL(string: "https://sport.bbc.co.uk")!, current: source)))
        XCTAssertTrue(guardPolicy.allows(.init(destination: URL(string: "https://example.com")!, current: source, historyOrReload: true)))
    }
    func testCrossSiteNeedsMatchingRecentLink() {
        let target = URL(string: "https://example.com/path")!
        XCTAssertFalse(guardPolicy.allows(.init(destination: target, current: source)))
        XCTAssertTrue(guardPolicy.allows(.init(destination: target, current: source, clickedLink: target, gestureAge: 1)))
        XCTAssertFalse(guardPolicy.allows(.init(destination: target, current: source, clickedLink: target, gestureAge: 2.1)))
        XCTAssertFalse(guardPolicy.allows(.init(destination: target, current: source, clickedLink: source, gestureAge: 0.1)))
    }
    func testIframeCannotMoveTopAcrossSites() {
        let target = URL(string: "https://accounts.google.com")!
        XCTAssertFalse(guardPolicy.allows(.init(destination: target, current: source, mainFrame: false, clickedLink: target, gestureAge: 0.2, allowedSites: ["bbc.co.uk"])))
    }
    func testServerRedirectAndExplicitLoads() {
        for host in ["example.com", "example.net", "example.org"] {
            let target = URL(string: "https://\(host)")!
            XCTAssertTrue(guardPolicy.allows(.init(destination: target, current: source, serverRedirect: true)))
            XCTAssertTrue(guardPolicy.allows(.init(destination: target, current: source, native: true)))
            XCTAssertFalse(guardPolicy.allows(.init(destination: target, current: source)))
        }
    }
    func testFormsAndExceptions() {
        let target = URL(string: "https://example.com")!
        XCTAssertTrue(guardPolicy.allows(.init(destination: target, current: source, form: true)))
        XCTAssertTrue(guardPolicy.allows(.init(destination: target, current: source, allowedSites: ["bbc.co.uk"])))
        for host in NavigationGuard.signInHosts {
            XCTAssertTrue(guardPolicy.allows(.init(destination: URL(string: "https://\(host)")!, current: source)))
        }
        XCTAssertFalse(guardPolicy.allows(.init(destination: URL(string: "https://accounts.google.com.evil.test")!, current: source)))
    }
    func testPopupRules() {
        let target = URL(string: "https://example.com")!
        XCTAssertFalse(guardPolicy.allows(.init(destination: target, current: source, popup: true)))
        XCTAssertFalse(guardPolicy.allows(.init(destination: target, current: source, popup: true, linkActivated: true)))
        XCTAssertTrue(guardPolicy.allows(.init(destination: target, current: source, popup: true, linkActivated: true, clickedLink: target, gestureAge: 0.2)))
        XCTAssertFalse(guardPolicy.allows(.init(destination: target, current: source, mainFrame: false, popup: true, linkActivated: true, clickedLink: target, gestureAge: 0.2)))
    }
    func testExternalSchemesNeverOpen() {
        for url in ["javascript:alert(1)", "itms-apps://example.com", "file:///tmp/test"] {
            XCTAssertFalse(guardPolicy.allows(.init(destination: URL(string: url)!, current: source, native: true)))
        }
    }
}
