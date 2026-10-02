import Foundation
import CryptoKit
import WebKit

// Preconverted snapshots; WebKit compiles them locally using its public API.
actor BundledBlocker {
    struct Snapshot: Codable, Sendable {
        struct Shard: Codable, Sendable {
            let file: String
            let sha256: String
            let ruleCount: Int
        }
        let createdAt: Date
        let converterVersion: String
        let shards: [Shard]
    }
    private let directory: URL?
    private let prefix: String

    init(directory: URL? = Bundle.main.url(forResource: "BlockingSnapshot", withExtension: nil),
         prefix: String = "iris-bundled-") {
        self.directory = directory
        self.prefix = prefix
    }

    func load() async throws -> BlockerEngine.Manifest {
        guard let directory else { throw FilterError.conversion("Bundled protection is missing") }
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: directory.appendingPathComponent("snapshot.json")))
        guard !snapshot.shards.isEmpty else { throw FilterError.conversion("Bundled protection has no rules") }
        var identifiers: [String] = []
        var created: [String] = []
        let start = Date()
        do {
            for shard in snapshot.shards {
                try Task.checkCancellation()
                guard shard.file == URL(fileURLWithPath: shard.file).lastPathComponent,
                      (1...49_000).contains(shard.ruleCount) else { throw FilterError.conversion("Invalid bundled shard") }
                let id = prefix + shard.sha256
                if try await Self.cached(id) {
                    identifiers.append(id)
                    continue
                }
                let compressed = try Data(contentsOf: directory.appendingPathComponent(shard.file))
                let data = try (compressed as NSData).decompressed(using: .lzfse) as Data
                let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                guard digest == shard.sha256, let json = String(data: data, encoding: .utf8) else {
                    throw FilterError.conversion("Bundled shard checksum failed")
                }
                try await Self.compile(json, id: id)
                created.append(id)
                identifiers.append(id)
            }
            try Task.checkCancellation()
            return BlockerEngine.Manifest(identifiers: identifiers, updatedAt: snapshot.createdAt,
                ruleCount: snapshot.shards.reduce(0) { $0 + $1.ruleCount }, conversionSeconds: 0,
                compilationSeconds: Date().timeIntervalSince(start))
        } catch {
            for id in created { await Self.remove(id) }
            throw error
        }
    }

    @MainActor private static func cached(_ id: String) async throws -> Bool {
        // A cache/version mismatch is recoverable by compiling the bundled JSON again.
        (try? await WKContentRuleListStore.default().contentRuleList(forIdentifier: id)) != nil
    }

    @MainActor private static func compile(_ json: String, id: String) async throws {
        guard try await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: id, encodedContentRuleList: json) != nil else {
            throw FilterError.conversion("Bundled compilation returned no rules")
        }
    }

    @MainActor private static func remove(_ id: String) async {
        try? await WKContentRuleListStore.default().removeContentRuleList(forIdentifier: id)
    }
}
