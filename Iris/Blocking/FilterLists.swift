import Foundation

enum FilterLists {
    struct Source: Sendable {
        let id: String
        let url: URL
        var hostsFormat = false
    }
    // Canonical URLs from uBlock's assets.json; see THIRD_PARTY.md.
    static let sources: [Source] = [
        .init(id: "ubo-ads", url: URL(string: "https://ublockorigin.github.io/uAssets/filters/filters.txt")!),
        .init(id: "ubo-privacy", url: URL(string: "https://ublockorigin.github.io/uAssets/filters/privacy.txt")!),
        .init(id: "ubo-badware", url: URL(string: "https://ublockorigin.github.io/uAssets/filters/badware.txt")!),
        .init(id: "ubo-unbreak", url: URL(string: "https://ublockorigin.github.io/uAssets/filters/unbreak.txt")!),
        .init(id: "easylist", url: URL(string: "https://ublockorigin.github.io/uAssets/thirdparties/easylist.txt")!),
        .init(id: "easyprivacy", url: URL(string: "https://ublockorigin.github.io/uAssets/thirdparties/easyprivacy.txt")!),
        .init(id: "peter-lowe", url: URL(string: "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=1&mimetype=plaintext")!, hostsFormat: true)
    ]

    static func download(to directory: URL) async throws -> [String] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try await withThrowingTaskGroup(of: (Int, [String]).self) { group in
            for (index, source) in sources.enumerated() {
                group.addTask {
                    var request = URLRequest(url: source.url)
                    request.timeoutInterval = 45
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                          data.count < 15_000_000, var text = String(data: data, encoding: .utf8),
                          !text.lowercased().contains("<html") else { throw FilterError.invalidDownload(source.id) }
                    text.makeContiguousUTF8()
                    let lines = normalized(text, hostsFormat: source.hostsFormat)
                    guard lines.count > 100 else { throw FilterError.invalidDownload(source.id) }
                    try Task.checkCancellation()
                    try data.write(to: directory.appendingPathComponent(source.id + ".txt"), options: .atomic)
                    return (index, lines)
                }
            }
            var lists: [(Int, [String])] = []
            for try await list in group { lists.append(list) }
            return lists.sorted { $0.0 < $1.0 }.flatMap(\.1)
        }
    }

    static func normalized(_ text: String, hostsFormat: Bool) -> [String] {
        text.components(separatedBy: .newlines).compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { return nil }
            if !hostsFormat { return line }
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2, fields[0] == "127.0.0.1" || fields[0] == "0.0.0.0" else { return nil }
            let host = String(fields[1]).lowercased()
            guard host.contains("."), !host.contains(where: { !( $0.isLetter || $0.isNumber || $0 == "-" || $0 == ".") }) else { return nil }
            return "||\(host)^"
        }
    }
}

enum FilterError: LocalizedError {
    case invalidDownload(String)
    case conversion(String)
    var errorDescription: String? {
        switch self {
        case .invalidDownload(let name): return "Could not download a valid \(name) filter list. Existing rules are still active."
        case .conversion(let detail): return "Filter conversion failed: \(detail)"
        }
    }
}
