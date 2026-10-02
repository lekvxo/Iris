import Foundation

struct PublicSuffix: Sendable {
    private let exact: Set<String>
    private let wildcard: Set<String>
    private let exceptions: Set<String>

    static let bundled: PublicSuffix = {
        guard let url = Bundle.main.url(forResource: "public_suffix_list", withExtension: "dat"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            preconditionFailure("Public Suffix List missing")
        }
        return PublicSuffix(text: text)
    }()

    init(text: String) {
        var exact = Set<String>(), wildcard = Set<String>(), exceptions = Set<String>()
        for line in text.components(separatedBy: .newlines) {
            let rule = line.trimmingCharacters(in: .whitespaces)
            guard !rule.isEmpty, !rule.hasPrefix("//") else { continue }
            if rule.hasPrefix("!") { exceptions.insert(String(rule.dropFirst())) }
            else if rule.hasPrefix("*.") { wildcard.insert(String(rule.dropFirst(2))) }
            else { exact.insert(rule) }
        }
        self.exact = exact
        self.wildcard = wildcard
        self.exceptions = exceptions
    }

    func registrableDomain(_ host: String) -> String {
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let labels = host.split(separator: ".").map(String.init)
        guard labels.count > 1, !host.contains(":"), !labels.allSatisfy({ Int($0) != nil }) else { return host }
        var suffixLength = 1
        for index in labels.indices {
            let tail = labels[index...].joined(separator: ".")
            if exceptions.contains(tail) {
                suffixLength = labels.count - index - 1
                break
            }
            if exact.contains(tail) { suffixLength = max(suffixLength, labels.count - index) }
            if index > 0, wildcard.contains(tail) { suffixLength = max(suffixLength, labels.count - index + 1) }
        }
        return labels.suffix(min(labels.count, suffixLength + 1)).joined(separator: ".")
    }
}
