import XCTest
@testable import Iris

final class PageBlockingActivityTests: XCTestCase {
    func testDuplicatesKindsAndPageReset() {
        var activity = PageBlockingActivity()
        let url = URL(string: "https://unwanted.example/popup")!
        let firstPage = activity.pageID
        activity.record(url, kind: .popup)
        activity.record(url, kind: .popup)
        XCTAssertEqual(activity.count, 1, "Script reporting and delegate denial must not double-count a destination")
        XCTAssertEqual(activity.summary, "Blocked 1 popup")
        activity.record(url, kind: .redirect)
        XCTAssertEqual(activity.count, 2)
        XCTAssertEqual(activity.summary, "Blocked 1 popup and 1 redirect")
        activity.reset()
        XCTAssertNotEqual(activity.pageID, firstPage)
        XCTAssertTrue(activity.items.isEmpty)
        XCTAssertEqual(activity.badgeTitle, "0")
        XCTAssertEqual(activity.summary, "No popups or redirects blocked on this page")
    }

    func testAggressivePageCannotGrowDetailsWithoutBound() {
        var activity = PageBlockingActivity()
        for index in 0..<1_000 {
            activity.record(URL(string: "https://unwanted.example/\(index)")!, kind: .popup)
        }
        XCTAssertEqual(activity.items.count, PageBlockingActivity.detailLimit)
        XCTAssertEqual(activity.badgeTitle, "200+")
        XCTAssertEqual(activity.summary, "Blocked 200+ unwanted destinations")
        activity.reset()
        XCTAssertFalse(activity.hasMore)
    }
}
