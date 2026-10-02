import XCTest
import SwiftData
import WebKit
import UIKit
import CryptoKit
@testable import Iris

@MainActor final class BundledBlockerTests: XCTestCase {
    func testOfflineFirstLaunchCompilesAllBundledShardsAndKeepsThemAfterRefreshFailure() async throws {
        let directory = try XCTUnwrap(Bundle.main.url(forResource: "BlockingSnapshot", withExtension: nil))
        let snapshot = try JSONDecoder().decode(BundledBlocker.Snapshot.self, from: Data(contentsOf: directory.appendingPathComponent("snapshot.json")))
        XCTAssertEqual(snapshot.converterVersion, "4.3.0")
        XCTAssertEqual(snapshot.shards.count, 8)
        XCTAssertGreaterThan(snapshot.shards.reduce(0) { $0 + $1.ruleCount }, 100_000)
        for shard in snapshot.shards {
            let compressed = try Data(contentsOf: directory.appendingPathComponent(shard.file))
            let data = try (compressed as NSData).decompressed(using: .lzfse) as Data
            XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), shard.sha256)
            XCTAssertEqual(try (JSONSerialization.jsonObject(with: data) as? [[String: Any]])?.count, shard.ruleCount)
            XCTAssertLessThanOrEqual(shard.ruleCount, 49_000)
        }
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let prefix = "iris-test-bundled-\(UUID().uuidString)-"
        let bundled = BundledBlocker(directory: directory, prefix: prefix)
        let controller = BlockerController(engine: BlockerEngine(root: root), bundled: bundled, refreshOperation: {
            throw URLError(.notConnectedToInternet)
        })
        let settings = SettingsStore(configuration: ModelConfiguration(isStoredInMemoryOnly: true))
        controller.setWorkAllowed(false)
        let preparation = Task { await controller.prepare(settings: settings) }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(controller.isReady, "Cold compilation must wait while backgrounded or hot")
        controller.setWorkAllowed(true)
        await preparation.value
        await controller.prepare(settings: settings)
        XCTAssertTrue(controller.isReady, "Cold startup must install rules before navigating, even offline")
        let count = controller.ruleCount
        XCTAssertEqual(count, snapshot.shards.reduce(0) { $0 + $1.ruleCount })
        await controller.refresh()
        XCTAssertTrue(controller.isReady)
        XCTAssertEqual(controller.ruleCount, count)
        XCTAssertNotNil(controller.status)
        // Apply the actual bundled rules to a page without making a network request.
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = try XCTUnwrap(scene.windows.first(where: \.isKeyWindow))
        window.addSubview(view)
        controller.register(view, settings: settings)
        defer { view.removeFromSuperview(); controller.unregister(view) }
        view.loadHTMLString("<html><body><ins id='fixture' class='adsbygoogle' data-ad-client='fixture'>Advert</ins></body></html>", baseURL: URL(string: "https://example.com")!)
        var display: String?
        for _ in 0..<450 {
            if !view.isLoading, let value = try? await view.evaluateJavaScript("document.getElementById('fixture') ? getComputedStyle(document.getElementById('fixture')).display : null"),
               let text = value as? String { display = text; break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(display, "none", "The offline startup path must actually hide an EasyList ad element")
        let reloaded = try await bundled.load()
        XCTAssertEqual(reloaded.identifiers.count, snapshot.shards.count, "Compiled bundled shards must reopen without a download")
        for id in reloaded.identifiers { try await WKContentRuleListStore.default().removeContentRuleList(forIdentifier: id) }
    }

    func testFreshRuntimeCacheTakesPriorityOverMissingBundle() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = "iris-test-runtime-\(UUID().uuidString)"
        let json = "[{\"trigger\":{\"url-filter\":\"ads\\\\.example\"},\"action\":{\"type\":\"block\"}}]"
        _ = try await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: id, encodedContentRuleList: json)
        let manifest = BlockerEngine.Manifest(identifiers: [id], updatedAt: Date(), ruleCount: 1, conversionSeconds: 0, compilationSeconds: 0)
        try JSONEncoder().encode(manifest).write(to: root.appendingPathComponent("manifest.json"))
        let controller = BlockerController(engine: BlockerEngine(root: root), bundled: BundledBlocker(directory: nil), refreshOperation: {
            XCTFail("A fresh runtime cache should not refresh at startup")
            throw URLError(.notConnectedToInternet)
        })
        await controller.prepare(settings: SettingsStore(configuration: ModelConfiguration(isStoredInMemoryOnly: true)))
        XCTAssertTrue(controller.isReady)
        XCTAssertEqual(controller.ruleCount, 1)
        XCTAssertNil(controller.status)
        try await WKContentRuleListStore.default().removeContentRuleList(forIdentifier: id)
    }

    func testCorruptBundleFailsWithoutInstallingPartialProtection() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let data = Data("[]".utf8)
        try ((data as NSData).compressed(using: .lzfse) as Data).write(to: root.appendingPathComponent("bad.lzfse"))
        let snapshot = BundledBlocker.Snapshot(createdAt: Date(), converterVersion: "4.3.0", shards: [
            .init(file: "bad.lzfse", sha256: "invalid", ruleCount: 1)
        ])
        try JSONEncoder().encode(snapshot).write(to: root.appendingPathComponent("snapshot.json"))
        do { _ = try await BundledBlocker(directory: root, prefix: "iris-test-invalid-").load(); XCTFail("Corrupt snapshot was accepted") }
        catch { XCTAssertTrue(error.localizedDescription.contains("checksum")) }
    }
}
