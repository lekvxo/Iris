import XCTest
import WebKit
@testable import Iris

final class LiveFilterTests: XCTestCase {
    @MainActor func testFullFilterDownloadConversionAndCompilation() async throws {
        guard ProcessInfo.processInfo.environment["IRIS_LIVE_FILTERS"] == "1" else {
            throw XCTSkip("Opt-in network smoke check: IRIS_LIVE_FILTERS=1 Scripts/check-phase.sh live")
        }
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = BlockerEngine(root: root)
        let manifest = try await engine.refresh()
        XCTAssertGreaterThan(manifest.ruleCount, 10000)
        XCTAssertFalse(manifest.identifiers.isEmpty)
        let sourceFiles = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Sources").path)
        XCTAssertEqual(sourceFiles.count, FilterLists.sources.count)
        let cache = try await engine.cached()
        XCTAssertEqual(cache?.identifiers, manifest.identifiers)
        XCTAssertFalse(manifest.needsRefresh())
        for id in manifest.identifiers {
            let list = try await WKContentRuleListStore.default().contentRuleList(forIdentifier: id)
            XCTAssertNotNil(list)
            try await WKContentRuleListStore.default().removeContentRuleList(forIdentifier: id)
        }
    }
}
