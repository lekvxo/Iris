import XCTest
import SwiftData
@testable import Iris

final class HistoryTests: XCTestCase {
    @MainActor private func memoryContainer() throws -> ModelContainer {
        try ModelContainer(for: HistoryEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @MainActor func testDeduplicatesWithinLocalCalendarDayAndUpdatesLateTitle() throws {
        let container = try memoryContainer()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        var visit = calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 23, minute: 30))!
        let history = HistoryStore(context: container.mainContext, calendar: calendar, now: { visit })
        let url = URL(string: "https://example.com/page")!
        history.record(url: url, title: "First")
        visit = visit.addingTimeInterval(60)
        history.record(url: url, title: "Second")
        var rows = try container.mainContext.fetch(FetchDescriptor<HistoryEntry>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.visitedAt, visit)
        XCTAssertEqual(rows.first?.title, "Second")
        visit = visit.addingTimeInterval(3600)
        history.record(url: url, title: "Next day")
        history.updateLatestTitle(url: url, title: "Late title")
        rows = try container.mainContext.fetch(FetchDescriptor<HistoryEntry>(sortBy: [SortDescriptor(\.visitedAt)]))
        XCTAssertEqual(rows.map(\.title), ["Second", "Late title"])
        XCTAssertNil(history.error)
        for row in rows { container.mainContext.delete(row) }
        try container.mainContext.save()
        history.updateLatestTitle(url: url, title: "Arrived after clearing")
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<HistoryEntry>()).isEmpty)
    }

    @MainActor func testSkipsNonWebsiteURLs() throws {
        let container = try memoryContainer()
        let history = HistoryStore(context: container.mainContext)
        for address in ["about:blank", "file:///tmp/page.html", "data:text/html,hello", "mailto:max@example.com", "blob:https://example.com/id", "iris://page", "https:/no-host"] {
            history.record(url: URL(string: address)!, title: "Skipped")
        }
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<HistoryEntry>()).isEmpty)
        history.record(url: URL(string: "https://example.com")!, title: "")
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<HistoryEntry>()).first?.title, "example.com")
    }
    @MainActor func testAddingHistoryPreservesExistingSavedDataAndSurvivesReopening() throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("history.store")
        let oldSchema = Schema([SavedSite.self, SitePermission.self])
        do {
            let container = try ModelContainer(for: oldSchema, configurations: [
                ModelConfiguration(schema: oldSchema, url: storeURL, cloudKitDatabase: .none)
            ])
            container.mainContext.insert(SavedSite(url: URL(string: "https://example.com/saved")!, title: "Saved"))
            container.mainContext.insert(SitePermission(domain: "example.com", allowsNavigation: true))
            try container.mainContext.save()
        }
        let schema = Schema([SavedSite.self, SitePermission.self, HistoryEntry.self])
        let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        let visit = Date(timeIntervalSince1970: 1_700_000_000)
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<SavedSite>()).first?.title, "Saved")
            XCTAssertTrue(try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<SitePermission>()).first).allowsNavigation)
            container.mainContext.insert(HistoryEntry(url: URL(string: "https://example.com/page")!, title: "Page", visitedAt: visit))
            try container.mainContext.save()
        }
        let reopened = try ModelContainer(for: schema, configurations: [configuration])
        let entry = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<HistoryEntry>()).first)
        XCTAssertEqual(entry.url, "https://example.com/page")
        XCTAssertEqual(entry.title, "Page")
        XCTAssertEqual(entry.host, "example.com")
        XCTAssertEqual(entry.visitedAt, visit)
    }
}
