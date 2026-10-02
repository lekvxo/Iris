import Foundation
import ContentBlockerConverter
import FilterEngine
import OSLog

actor YouTubeRuleStore {
    static let shared = YouTubeRuleStore()
    private let root: URL
    private let sources: URL?
    private var engine: FilterEngine?
    private var storageURL: URL?
    private let logger = Logger(subsystem: "com.max.iris", category: "YouTubeScriptlets")

    init(root: URL = URL.applicationSupportDirectory.appendingPathComponent("YouTubePilot"),
         sources: URL? = Bundle.main.url(forResource: "BlockingSnapshot", withExtension: nil)?.appendingPathComponent("Sources")) {
        self.root = root
        self.sources = sources
    }

    func calls(for url: URL) throws -> [YouTubeRuleAdapter.Call] {
        guard YouTubeRuleAdapter.contains(url) else { return [] }
        try prepare()
        guard let engine else { return [] }
        var calls: Set<YouTubeRuleAdapter.Call> = []
        for rule in engine.findAll(for: Request(url: url)) where rule.action.contains(.scriptlet) {
            guard let text = rule.cosmeticContent else { continue }
            if let call = try YouTubeRuleAdapter.call(text) { calls.insert(call) }
            else { logger.notice("Skipped an unsupported YouTube scriptlet; bundled runtime is unchanged") }
        }
        return calls.sorted { ($0.name, $0.args.joined(separator: "\u{1f}")) < ($1.name, $1.args.joined(separator: "\u{1f}")) }
    }

    private func prepare() throws {
        guard engine == nil else { return }
        let cache = root.appendingPathComponent("rules.json")
        if let data = try? Data(contentsOf: cache), let rules = try? JSONDecoder().decode([String].self, from: data),
           !rules.isEmpty, rules.count < 20_000, (try? install(rules)) != nil { return }
        guard let sources else { throw FilterError.conversion("Bundled YouTube rule sources missing") }
        var lines: [String] = []
        for source in FilterLists.sources {
            let compressed = try Data(contentsOf: sources.appendingPathComponent(source.id + ".txt.lzfse"))
            let data = try (compressed as NSData).decompressed(using: .lzfse) as Data
            lines += FilterLists.normalized(String(decoding: data, as: UTF8.self), hostsFormat: source.hostsFormat)
        }
        try install(Self.canonicalRules(lines))
    }

    // Called only after a complete, successful existing weekly/manual filter refresh.
    // Keep the last working scriptlet data when parsing or storage fails.
    func refresh(from lines: [String]) {
        do {
            let rules = try Self.canonicalRules(lines)
            try install(rules)
            try JSONEncoder().encode(rules).write(to: root.appendingPathComponent("rules.json"), options: .atomic)
            logger.notice("Updated YouTube rule data; runtime remains pinned to 2.3.1")
        } catch { logger.error("YouTube rule refresh failed: \(error.localizedDescription, privacy: .public)") }
    }

    static func canonicalRules(_ lines: [String]) throws -> [String] {
        var rules: [String] = []
        for line in lines {
            // Preserve native exception/badfilter handling in the existing FilterEngine.
            if line.hasPrefix("@@") || line.contains("$badfilter") { rules.append(line) }
            else if let rewritten = try YouTubeRuleAdapter.rewrite(line) { rules.append(rewritten) }
        }
        guard rules.contains(where: { $0.contains("#%#//scriptlet(") }), rules.count < 20_000 else {
            throw FilterError.conversion("No valid YouTube scriptlets")
        }
        return rules
    }

    private func install(_ rules: [String]) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent(UUID().uuidString + ".bin")
        do {
            let storage = try FilterRuleStorage(from: rules, for: .safari26, fileURL: file)
            let replacement = try FilterEngine(storage: storage)
            let previous = storageURL
            engine = replacement
            storageURL = file
            if let previous { try? FileManager.default.removeItem(at: previous) }
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw error
        }
    }
}
