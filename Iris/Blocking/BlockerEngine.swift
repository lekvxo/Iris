import Foundation
import ContentBlockerConverter
import WebKit
import OSLog

actor BlockerEngine {
    struct Manifest: Codable, Sendable {
        let identifiers: [String]
        let updatedAt: Date
        let ruleCount: Int
        let conversionSeconds: Double
        let compilationSeconds: Double
        func needsRefresh(now: Date = Date()) -> Bool {
            now.timeIntervalSince(updatedAt) >= 7 * 24 * 60 * 60
        }
    }
    private let root: URL
    private let logger = Logger(subsystem: "com.max.iris", category: "Filters")
    init(root: URL = URL.applicationSupportDirectory.appendingPathComponent("Filters")) { self.root = root }

    func cached() throws -> Manifest? {
        let url = root.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
    }

    func refresh() async throws -> Manifest {
        let rules = try await FilterLists.download(to: root.appendingPathComponent("Sources"))
        try Task.checkCancellation()
        let start = Date()
        let converted = try convert(rules: rules)
        let conversionSeconds = Date().timeIntervalSince(start)
        let compileStart = Date()
        let identifiers = try await Self.compile(converted.json)
        let manifest = Manifest(identifiers: identifiers, updatedAt: Date(), ruleCount: converted.count,
            conversionSeconds: conversionSeconds, compilationSeconds: Date().timeIntervalSince(compileStart))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(manifest).write(to: root.appendingPathComponent("manifest.json"), options: .atomic)
        logger.info("Compiled \(manifest.ruleCount) rules in \(manifest.identifiers.count) shards; convert \(manifest.conversionSeconds)s, compile \(manifest.compilationSeconds)s")
        return manifest
    }

    struct Converted: Sendable { let json: [String]; let count: Int }

    func convert(rules: [String], chunkSize: Int = 20_000) throws -> Converted {
        // Repeat exception/control rules in every input chunk so exceptions from
        // Unbreak can affect blocks from EasyList and other lists.
        let controls = rules.filter { $0.hasPrefix("@@") || $0.contains("#@#") || $0.contains("#@$#") || $0.contains("$badfilter") }
        var output: [String] = []
        var count = 0
        let controlSet = Set(controls)
        let input = rules.filter { !$0.hasPrefix("!") && !$0.hasPrefix("[") && !controlSet.contains($0) }
        for offset in stride(from: 0, to: input.count, by: chunkSize) {
            try Task.checkCancellation()
            let slice = Array(input[offset..<min(input.count, offset + chunkSize)])
            let result = try convertChunk(slice, controls: controls)
            output.append(contentsOf: result.json)
            count += result.count
        }
        guard !output.isEmpty else { throw FilterError.conversion("No compatible rules") }
        return Converted(json: output, count: count)
    }

    private func convertChunk(_ rules: [String], controls: [String]) throws -> Converted {
        // autodetect() falls back to Safari 13 on visionOS in converter 4.3.0.
        let result = ContentBlockerConverter().convertArray(rules: rules + controls, safariVersion: .safari26, advancedBlocking: false)
        if result.discardedSafariRules > 0 || result.safariRulesCount > 49_000 {
            guard rules.count > 1 else { throw FilterError.conversion("Rule shard exceeds safe cap") }
            let middle = rules.count / 2
            let first = try convertChunk(Array(rules[..<middle]), controls: controls)
            let second = try convertChunk(Array(rules[middle...]), controls: controls)
            return Converted(json: first.json + second.json, count: first.count + second.count)
        }
        guard result.safariRulesCount > 0 else { return Converted(json: [], count: 0) }
        return Converted(json: [result.safariRulesJSON], count: result.safariRulesCount)
    }

    @MainActor private static func compile(_ json: [String]) async throws -> [String] {
        let generation = UUID().uuidString
        var identifiers: [String] = []
        do {
            for (index, source) in json.enumerated() {
                try Task.checkCancellation()
                let id = "iris-\(generation)-\(index + 1)"
                _ = try await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: id, encodedContentRuleList: source)
                identifiers.append(id)
                try Task.checkCancellation()
            }
            return identifiers
        } catch {
            for id in identifiers { try? await WKContentRuleListStore.default().removeContentRuleList(forIdentifier: id) }
            throw error
        }
    }
}
