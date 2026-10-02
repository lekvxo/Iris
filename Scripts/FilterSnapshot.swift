import Foundation
import CryptoKit

@main struct FilterSnapshot {
    static func main() async throws {
        let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let sources = destination.appendingPathComponent("Sources", isDirectory: true)
        let rules = try await FilterLists.download(to: sources)
        // Reuse Iris's exact conversion/sharding behavior; do not maintain a second converter.
        let converted = try await BlockerEngine().convert(rules: rules)
        var shards: [BundledBlocker.Snapshot.Shard] = []
        for (index, json) in converted.json.enumerated() {
            let data = Data(json.utf8)
            let count = try (JSONSerialization.jsonObject(with: data) as! [[String: Any]]).count
            guard (1...49_000).contains(count) else { throw FilterError.conversion("Invalid snapshot rule cap") }
            let file = "rules-\(index + 1).json.lzfse"
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            try ((data as NSData).compressed(using: .lzfse) as Data).write(to: destination.appendingPathComponent(file))
            shards.append(.init(file: file, sha256: digest, ruleCount: count))
        }
        // Preserve complete corresponding filter sources and their license notices in the bundle.
        var notices = "Iris bundled blocking snapshot. SafariConverterLib 4.3.0, advancedBlocking=false, Safari 26 rules.\nFull source lists and embedded notices are in Sources/*.txt.lzfse.\n"
        for source in FilterLists.sources {
            let file = sources.appendingPathComponent(source.id + ".txt")
            let data = try Data(contentsOf: file)
            try ((data as NSData).compressed(using: .lzfse) as Data).write(to: file.appendingPathExtension("lzfse"))
            let headers = String(decoding: data, as: UTF8.self).components(separatedBy: .newlines)
                .prefix(60).filter { $0.hasPrefix("!") || $0.hasPrefix("#") }.joined(separator: "\n")
            notices += "\n\(source.id): \(source.url.absoluteString)\n\(headers)\n"
            try FileManager.default.removeItem(at: file)
        }
        try notices.write(to: destination.appendingPathComponent("NOTICE.txt"), atomically: true, encoding: .utf8)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let snapshot = BundledBlocker.Snapshot(createdAt: Date(), converterVersion: "4.3.0", shards: shards)
        try encoder.encode(snapshot).write(to: destination.appendingPathComponent("snapshot.json"))
        print("Bundled \(converted.count) rules in \(shards.count) shards from all \(FilterLists.sources.count) sources")
    }
}
