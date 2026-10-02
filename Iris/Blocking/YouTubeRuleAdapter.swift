import Foundation
import ContentBlockerConverter

// Repair uBO argument quoting before conversion, rather than guessing at broken output.
enum YouTubeRuleAdapter {
    struct Call: Codable, Hashable, Sendable {
        let name: String
        let runtimeName: String
        let args: [String]
    }

    static func contains(_ url: URL?) -> Bool {
        guard let url, ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host?.lowercased() else { return false }
        return host == "youtube.com" || host.hasSuffix(".youtube.com")
    }

    // Only reviewed implementations can be invoked by downloaded rule data.
    static func runtimeName(for name: String) -> String? {
        switch name {
        case "ubo-trusted-replace-fetch-response": return "trusted-replace-fetch-response"
        case "ubo-trusted-replace-xhr-response": return "trusted-replace-xhr-response"
        case "ubo-set", "ubo-json-prune", "ubo-json-prune-fetch-response", "ubo-no-xhr-if": return name
        default: return nil
        }
    }

    static func rewrite(_ line: String) throws -> String? {
        guard !line.hasPrefix("!"), let range = line.range(of: "##+js(") ?? line.range(of: "#@#+js("),
              line.hasSuffix(")") else { return nil }
        let domains = String(line[..<range.lowerBound])
        guard domains.split(separator: ",").contains(where: { token in
            let host = token.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "~", with: "")
            return host == "youtube.com" || host.hasSuffix(".youtube.com")
        }) else { return nil }
        let values = try arguments(String(line[range.upperBound..<line.index(before: line.endIndex)]))
        guard let name = values.first, !name.isEmpty else { throw FilterError.conversion("Empty YouTube scriptlet") }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let encoded = String(decoding: try encoder.encode(["ubo-" + name] + values.dropFirst()), as: UTF8.self)
        let marker = line[range].contains("@") ? "#@%#" : "#%#"
        return domains + marker + "//scriptlet(" + encoded.dropFirst().dropLast() + ")"
    }

    static func arguments(_ text: String) throws -> [String] {
        let characters = Array(text)
        var output: [String] = [], value = ""
        var quote: Character?
        var index = 0
        while index < characters.count {
            let char = characters[index]
            if char == "\\", index + 1 < characters.count {
                let next = characters[index + 1]
                if next == "," || next == quote || (quote != nil && next == "\\") {
                    value.append(next); index += 2; continue
                }
                value.append(char); index += 1; continue
            }
            if let delimiter = quote {
                if char == delimiter { quote = nil } else { value.append(char) }
            } else if value.trimmingCharacters(in: .whitespaces).isEmpty && ["'", "\"", "`"].contains(char) {
                quote = char
            } else if char == "," {
                output.append(value.trimmingCharacters(in: .whitespaces)); value = ""
            } else { value.append(char) }
            index += 1
        }
        guard quote == nil else { throw FilterError.conversion("Unclosed YouTube scriptlet argument") }
        output.append(value.trimmingCharacters(in: .whitespaces))
        return output
    }

    static func call(_ text: String) throws -> Call? {
        let parsed = try ScriptletParser.parse(cosmeticRuleContent: text)
        guard let runtimeName = runtimeName(for: parsed.name), parsed.args.count <= 16,
              parsed.args.allSatisfy({ $0.utf8.count <= 16_384 }) else { return nil }
        return Call(name: parsed.name, runtimeName: runtimeName, args: parsed.args)
    }
}
