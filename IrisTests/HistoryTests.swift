import XCTest
import SwiftData
@testable import Iris

final class HistoryTests: XCTestCase {
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
