import Foundation

enum InputRouter {
    static func destination(for input: String) -> URL {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), validHost(url.host) {
            return url
        }
        if !text.contains(where: \.isWhitespace), let url = URL(string: "https://" + text), validHost(url.host),
           let host = url.host, host.contains(".") || host == "localhost" {
            return url
        }
        var components = URLComponents(string: "https://www.google.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: text)]
        return components.url!
    }

    private static func validHost(_ host: String?) -> Bool {
        guard let host, !host.isEmpty else { return false }
        if host == "localhost" { return true }
        return host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            !label.isEmpty && label.first != "-" && label.last != "-" &&
            label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
    }
}
