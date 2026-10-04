import XCTest
@testable import Iris

@MainActor final class BrowserTabsTests: XCTestCase {
    func testNewDestinationsAndDuplicatesStayInTabsWithIndependentState() {
        let tabs = BrowserTabs()
        let opener = tabs.selected
        opener.model.title = "First page"
        let url = URL(string: "https://example.com/next")!
        opener.model.openWindow?(WindowRequest(url: url))
        XCTAssertEqual(tabs.tabs.count, 2)
        let second = tabs.selected
        XCTAssertEqual(second.initialURL, url)
        XCTAssertTrue(opener.model.isBackgrounded)
        second.model.openWindow?(WindowRequest(url: url))
        XCTAssertEqual(tabs.tabs.count, 3)
        XCTAssertFalse(tabs.selected.model === second.model)
        tabs.select(opener.id)
        XCTAssertEqual(tabs.selected.model.title, "First page")
        XCTAssertFalse(opener.model.isBackgrounded)
        second.model.closeWindow?()
        XCTAssertEqual(tabs.tabs.count, 2)
        XCTAssertEqual(tabs.selectedID, opener.id)
    }

    func testPinOrderAndRestorationLoadOnlySelectedTab() {
        let tabs = BrowserTabs()
        let first = tabs.selected
        let pinned = tabs.open(WindowRequest(url: URL(string: "https://apple.com")!))
        pinned.isPinned = true
        tabs.select(first.id)
        XCTAssertEqual(tabs.ordered.first?.id, pinned.id)
        let restored = BrowserTabs()
        restored.restore(tabs.snapshot)
        XCTAssertEqual(restored.tabs.count, 2)
        XCTAssertEqual(restored.selectedID, first.id)
        XCTAssertTrue(restored.ordered.first?.isPinned == true)
        XCTAssertEqual(restored.tabs.filter(\.hasBeenSelected).count, 1)
        restored.close(first.id)
        XCTAssertEqual(restored.selectedID, pinned.id)
        restored.close(pinned.id)
        XCTAssertEqual(restored.tabs.count, 1)
        XCTAssertEqual(restored.selected.initialURL, BrowserTabs.home)
        XCTAssertTrue(restored.selected.hasBeenSelected)
    }
}
