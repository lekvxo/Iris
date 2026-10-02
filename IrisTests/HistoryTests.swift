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

    @MainActor func testSearchUsesSwiftDataTitleAndURLAndBrowseLimitsNewest500() throws {
        let container = try memoryContainer()
        for index in 0..<501 {
            container.mainContext.insert(HistoryEntry(url: URL(string: "https://example.com/\(index)")!,
                title: index == 0 ? "Café SPACE" : "Page \(index)", visitedAt: Date(timeIntervalSince1970: Double(index))))
        }
        container.mainContext.insert(HistoryEntry(url: URL(string: "https://EXAMPLE.com/Needle")!, title: "Address match", visitedAt: .distantPast))
        try container.mainContext.save()
        let recent = try container.mainContext.fetch(HistoryStore.fetchDescriptor())
        XCTAssertEqual(recent.count, 500)
        XCTAssertEqual(recent.first?.url, "https://example.com/500")
        XCTAssertFalse(recent.contains { $0.title == "Café SPACE" })
        XCTAssertEqual(try container.mainContext.fetch(HistoryStore.fetchDescriptor(search: "cafe space")).map(\.title), ["Café SPACE"])
        XCTAssertEqual(try container.mainContext.fetch(HistoryStore.fetchDescriptor(search: "NEEDLE")).map(\.title), ["Address match"])
        XCTAssertTrue(try container.mainContext.fetch(HistoryStore.fetchDescriptor(search: "missing")).isEmpty)
    }

    @MainActor func testGroupingUsesLocalDaysAcrossDaylightSavingTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 12))!
        let offsets = [0, 0, -1, -3, -8]
        let rows = offsets.map { offset in
            HistoryEntry(url: URL(string: "https://example.com/\(offset)")!, title: "Page",
                         visitedAt: calendar.date(byAdding: .day, value: offset, to: now)!)
        }
        let sections = HistoryDay.sections(rows, calendar: calendar, now: now)
        XCTAssertEqual(sections.count, 4)
        XCTAssertEqual(sections[0].title, "Today")
        XCTAssertEqual(sections[0].entries.count, 2)
        XCTAssertEqual(sections[1].title, "Yesterday")
        let weekday = DateFormatter()
        weekday.calendar = calendar
        weekday.timeZone = calendar.timeZone
        weekday.setLocalizedDateFormatFromTemplate("EEEE")
        XCTAssertEqual(sections[2].title, weekday.string(from: sections[2].id))
        XCTAssertTrue(sections[3].title.contains("2026"))
    }

    @MainActor func testClearRangesIncludeTheirStartAndKeepOtherRows() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        // Yesterday was a 25-hour day: subtracting 48 hours is not a calendar boundary.
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 12))!
        let hour = now.addingTimeInterval(-3600)
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let dates = [yesterday.addingTimeInterval(-1), yesterday, today.addingTimeInterval(-1), today,
                     hour.addingTimeInterval(-1), hour, now, now.addingTimeInterval(1)]
        let expectedRemaining: [HistoryClearRange: [Int]] = [.hour: [0, 1, 2, 3, 4, 7], .today: [0, 1, 2, 7],
                                                           .todayAndYesterday: [0, 7], .all: []]
        for range in HistoryClearRange.allCases {
            let container = try memoryContainer()
            let context = container.mainContext
            for (index, date) in dates.enumerated() {
                context.insert(HistoryEntry(url: URL(string: "https://example.com/\(index)")!, title: String(index), visitedAt: date))
            }
            try context.save()
            let history = HistoryStore(context: context, calendar: calendar, now: { now })
            history.clear(range)
            XCTAssertNil(history.error)
            let remaining = try context.fetch(FetchDescriptor<HistoryEntry>()).compactMap { Int($0.title) }.sorted()
            XCTAssertEqual(remaining, expectedRemaining[range], range.title)
        }
    }

    @MainActor func testRetentionKeepsBoundaryAndDefaultsToOneYear() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 31, hour: 12))!
        let month = calendar.date(from: DateComponents(year: 2026, month: 2, day: 28, hour: 12))!
        let year = calendar.date(from: DateComponents(year: 2025, month: 3, day: 31, hour: 12))!
        let dates = [year.addingTimeInterval(-1), year, month.addingTimeInterval(-1), month, now]
        let remaining: [HistoryRetention: [Int]] = [.month: [3, 4], .year: [1, 2, 3, 4], .forever: [0, 1, 2, 3, 4]]
        for retention in HistoryRetention.allCases {
            let container = try memoryContainer()
            for (index, date) in dates.enumerated() {
                container.mainContext.insert(HistoryEntry(url: URL(string: "https://example.com/\(index)")!, title: String(index), visitedAt: date))
            }
            try container.mainContext.save()
            let history = HistoryStore(context: container.mainContext, calendar: calendar, now: { now })
            history.prune(keeping: retention)
            XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<HistoryEntry>()).compactMap { Int($0.title) }.sorted(), remaining[retention])
            XCTAssertNil(history.error)
        }
        let suite = "IrisHistoryTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(configuration: ModelConfiguration(isStoredInMemoryOnly: true), defaults: defaults)
        XCTAssertEqual(settings.historyRetention, .year)
        settings.historyRetention = .forever
        let reopened = SettingsStore(configuration: ModelConfiguration(isStoredInMemoryOnly: true), defaults: defaults)
        XCTAssertEqual(reopened.historyRetention, .forever)
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
