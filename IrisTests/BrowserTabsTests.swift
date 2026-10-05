import XCTest
import SwiftData
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

    func testSessionReopensLatestLinksPinsAndSelectionFromDisk() throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema([BrowserSessionRecord.self])
        let configuration = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("tabs.store"), cloudKitDatabase: .none)
        let windowID = UUID()
        var selectedID: UUID!
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let tabs = BrowserTabs(url: URL(string: "https://example.com/start")!)
            let first = tabs.selected
            let second = tabs.open(WindowRequest(url: URL(string: "https://apple.com/start")!))
            first.model.url = URL(string: "https://example.com/background-navigation")!
            second.model.url = URL(string: "https://apple.com/latest")!
            first.isPinned = true
            selectedID = second.id
            try BrowserSessionStore(context: container.mainContext).save(tabs.snapshot, windowID: windowID)
        }
        let reopened = try ModelContainer(for: schema, configurations: [configuration])
        let recovered = BrowserTabs()
        let newID = try BrowserSessionStore(context: reopened.mainContext).restore(recovered)
        XCTAssertNotEqual(newID, windowID)
        XCTAssertEqual(recovered.selectedID, selectedID)
        XCTAssertEqual(recovered.tabs.map(\.initialURL.absoluteString),
                       ["https://example.com/background-navigation", "https://apple.com/latest"])
        XCTAssertTrue(recovered.tabs[0].isPinned)
        XCTAssertEqual(recovered.tabs.filter(\.hasBeenSelected).count, 1)
        XCTAssertTrue(recovered.tabs.allSatisfy { $0.model.webView == nil })
    }

    func testFreshExplicitRequestAndRestoredScenePrecedence() throws {
        let container = try ModelContainer(for: BrowserSessionRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = BrowserSessionStore(context: container.mainContext)
        let saved = BrowserTabs(url: URL(string: "https://example.com/saved")!)
        let windowID = UUID()
        try store.save(saved.snapshot, windowID: windowID)
        let explicitURL = URL(string: "https://apple.com/new-link")!
        let fresh = BrowserTabs(url: explicitURL)
        _ = try store.restore(fresh, explicitRequest: true)
        XCTAssertEqual(fresh.selected.initialURL, explicitURL)
        XCTAssertFalse(store.didRestore)
        let restored = BrowserTabs(url: explicitURL)
        _ = try store.restore(restored, sceneSnapshot: saved.snapshot, windowID: windowID, explicitRequest: true)
        XCTAssertEqual(restored.selected.initialURL, saved.selected.initialURL)
        let newerScene = BrowserTabs(url: URL(string: "https://example.com/newer-scene")!)
        _ = try store.restore(restored, sceneSnapshot: newerScene.snapshot, windowID: windowID, explicitRequest: true)
        XCTAssertEqual(restored.selected.initialURL, newerScene.selected.initialURL)
    }

    func testWindowsRecoverIndependentlyAndCopyModels() throws {
        let container = try ModelContainer(for: BrowserSessionRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = BrowserSessionStore(context: container.mainContext)
        let firstID = UUID(), secondID = UUID()
        let first = BrowserTabs(url: URL(string: "https://example.com/first")!)
        let second = BrowserTabs(url: URL(string: "https://example.com/second")!)
        try store.save(first.snapshot, windowID: firstID)
        try store.save(second.snapshot, windowID: secondID)
        let restoredFirst = BrowserTabs(), restoredSecond = BrowserTabs(), fresh = BrowserTabs()
        XCTAssertEqual(try store.restore(restoredFirst, windowID: firstID), firstID)
        XCTAssertEqual(try store.restore(restoredSecond, windowID: secondID), secondID)
        XCTAssertEqual(restoredFirst.selected.initialURL, first.selected.initialURL)
        XCTAssertEqual(restoredSecond.selected.initialURL, second.selected.initialURL)
        let freshID = try store.restore(fresh)
        XCTAssertNotEqual(freshID, secondID)
        XCTAssertEqual(fresh.selected.initialURL, second.selected.initialURL)
        XCTAssertFalse(fresh.selected.model === restoredSecond.selected.model)
        fresh.selected.isPinned = true
        fresh.open(WindowRequest(url: URL(string: "https://example.com/third")!))
        fresh.close(fresh.tabs[0].id)
        try store.save(fresh.snapshot, windowID: freshID)
        let again = BrowserTabs()
        _ = try store.restore(again, windowID: secondID)
        XCTAssertEqual(again.tabs.count, 1)
        XCTAssertEqual(again.selected.initialURL, second.selected.initialURL)
        XCTAssertFalse(again.selected.isPinned)
        _ = try store.restore(again, windowID: freshID)
        XCTAssertEqual(again.selected.initialURL.absoluteString, "https://example.com/third")
    }

    func testMalformedSceneAndDiskSnapshotsFallBackWithoutCrossWindowRecovery() throws {
        let container = try ModelContainer(for: BrowserSessionRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = BrowserSessionStore(context: container.mainContext)
        let validID = UUID(), brokenID = UUID()
        let valid = BrowserTabs(url: URL(string: "https://example.com/valid")!)
        try store.save(valid.snapshot, windowID: validID)
        try store.save("{broken", windowID: brokenID)
        let tabs = BrowserTabs()
        _ = try store.restore(tabs, sceneSnapshot: "{broken")
        XCTAssertEqual(tabs.selected.initialURL, valid.selected.initialURL)
        let ownBroken = BrowserTabs()
        _ = try store.restore(ownBroken, sceneSnapshot: "{broken", windowID: brokenID)
        XCTAssertEqual(ownBroken.selected.initialURL, BrowserTabs.home)
        let original = BrowserTabs(url: URL(string: "https://apple.com/original")!)
        _ = try store.restore(original, sceneSnapshot: "{broken", explicitRequest: true)
        XCTAssertEqual(original.selected.initialURL.absoluteString, "https://apple.com/original")
        let snapshot = valid.snapshot.replacingOccurrences(of: "https", with: "file")
        XCTAssertFalse(original.restore(snapshot))
        XCTAssertEqual(original.selected.initialURL.absoluteString, "https://apple.com/original")
    }

    func testMalformedSceneAndOwnRecordRecoverValidLegacyURL() throws {
        let container = try ModelContainer(for: BrowserSessionRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = BrowserSessionStore(context: container.mainContext)
        let windowID = UUID()
        try store.save("{broken", windowID: windowID)
        let tabs = BrowserTabs()
        _ = try store.restore(tabs, sceneSnapshot: "{broken", windowID: windowID,
                              legacyURL: "https://example.com/legacy")
        XCTAssertTrue(store.didRestore)
        XCTAssertEqual(tabs.selected.initialURL.absoluteString, "https://example.com/legacy")
        let noRecord = BrowserTabs()
        _ = try store.restore(noRecord, sceneSnapshot: "{broken", windowID: UUID(),
                              legacyURL: "https://example.com/legacy-without-record")
        XCTAssertEqual(noRecord.selected.initialURL.absoluteString, "https://example.com/legacy-without-record")
        let invalid = BrowserTabs()
        _ = try store.restore(invalid, sceneSnapshot: "{broken", windowID: UUID(), legacyURL: "file:///tmp/page")
        XCTAssertFalse(store.didRestore)
        XCTAssertEqual(invalid.selected.initialURL, BrowserTabs.home)
        let explicit = BrowserTabs(url: URL(string: "https://apple.com/new-link")!)
        _ = try store.restore(explicit, explicitRequest: true, legacyURL: "https://example.com/legacy")
        XCTAssertEqual(explicit.selected.initialURL.absoluteString, "https://apple.com/new-link")
    }

    func testAddingSessionsPreservesExistingSavedSitesPermissionsAndHistory() throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("migration.store")
        let oldSchema = Schema([SavedSite.self, SitePermission.self, HistoryEntry.self])
        do {
            let container = try ModelContainer(for: oldSchema, configurations: [ModelConfiguration(schema: oldSchema, url: url, cloudKitDatabase: .none)])
            container.mainContext.insert(SavedSite(url: URL(string: "https://example.com/saved")!, title: "Saved"))
            container.mainContext.insert(SitePermission(domain: "example.com", allowsNavigation: true))
            container.mainContext.insert(HistoryEntry(url: URL(string: "https://example.com/history")!, title: "Visited"))
            try container.mainContext.save()
        }
        let schema = Schema([SavedSite.self, SitePermission.self, HistoryEntry.self, BrowserSessionRecord.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<SavedSite>()).first?.title, "Saved")
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<SitePermission>()).first?.allowsNavigation, true)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<HistoryEntry>()).first?.title, "Visited")
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<BrowserSessionRecord>()).isEmpty)
    }

}
