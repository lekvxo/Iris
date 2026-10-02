import Foundation

enum ScriptSource {
    static func read(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            preconditionFailure("Missing bundled script: \(name)")
        }
        return source
    }
}
