import XCTest
import SwiftData
import WebKit
@testable import Iris

@MainActor final class HistoryPrivacyTests: XCTestCase {
    func testHistoryAndWebsiteDataClearIndependently() async throws {
        let settings = SettingsStore(configuration: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = settings.container.mainContext
        let site = SavedSite(url: URL(string: "https://example.com/saved")!, title: "Saved")
        site.archiveFileName = "kept.webarchive"
        context.insert(site)
        try context.save()
        let data = WKWebsiteDataStore.nonPersistent()
        let cookie = try XCTUnwrap(HTTPCookie(properties: [.domain: "example.com", .path: "/", .name: "history-fixture", .value: "kept"]))
        await data.httpCookieStore.setCookie(cookie)
        settings.history.record(url: URL(string: "https://example.com/page")!, title: "Page")
        settings.history.clear(.all)
        let cookies = await data.httpCookieStore.allCookies()
        XCTAssertTrue(cookies.contains { $0.name == "history-fixture" && $0.value == "kept" })
        XCTAssertTrue(try context.fetch(FetchDescriptor<HistoryEntry>()).isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SavedSite>()).first?.archiveFileName, "kept.webarchive")
        settings.history.record(url: URL(string: "https://example.com/page")!, title: "Page")
        await data.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        let clearedCookies = await data.httpCookieStore.allCookies()
        XCTAssertFalse(clearedCookies.contains { $0.name == "history-fixture" })
        XCTAssertEqual(try context.fetch(FetchDescriptor<HistoryEntry>()).count, 1)
        XCTAssertNil(settings.history.error)
    }
}
