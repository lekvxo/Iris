import Foundation
import CryptoKit
import WebKit
import OSLog

@MainActor final class YouTubePilot {
    static let version = "2.3.1"
    private let store: YouTubeRuleStore
    private var runtime: String?
    private var scripts: [ObjectIdentifier: WKUserScript] = [:]
    private let logger = Logger(subsystem: "com.max.iris", category: "YouTubeScriptlets")
    init(store: YouTubeRuleStore = .shared) { self.store = store }

    func source(for url: URL, enabled: Bool) async throws -> String? {
        guard enabled, YouTubeRuleAdapter.contains(url) else { return nil }
        do {
            // youtube.com commonly redirects to www. Prepare both before the document starts.
            var plans: [String: [YouTubeRuleAdapter.Call]] = [:]
            for host in Set([url.host?.lowercased() ?? "", "youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "tv.youtube.com"]) {
                var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                components?.host = host
                if let destination = components?.url { plans[host] = try await store.calls(for: destination) }
            }
            if runtime == nil { runtime = try Self.readRuntime() }
            return try Self.source(runtime: runtime ?? "", plans: plans)
        } catch {
            logger.error("YouTube pilot preparation failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    func install(_ source: String?, in view: WKWebView) {
        let id = ObjectIdentifier(view)
        let controller = view.configuration.userContentController
        if let previous = scripts.removeValue(forKey: id) {
            let retained = controller.userScripts.filter { $0 !== previous }
            controller.removeAllUserScripts()
            for script in retained { controller.addUserScript(script) }
        }
        if let source {
            let script = WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .page)
            controller.addUserScript(script)
            scripts[id] = script
        }
    }

    func log(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, YouTubeRuleAdapter.contains(message.frameInfo.request.url),
              let body = message.body as? [String: Any], body["version"] as? String == Self.version else { return }
        let page = message.frameInfo.request.url?.absoluteString ?? ""
        let ran = (body["ran"] as? [String] ?? []).joined(separator: ", ")
        let failed = (body["failed"] as? [String] ?? []).joined(separator: ", ")
        logger.notice("Page \(page, privacy: .public) runtime=\(Self.version, privacy: .public) invoked=[\(ran, privacy: .public)] failed=[\(failed, privacy: .public)]")
    }

    static func readRuntime() throws -> String {
        guard let directory = Bundle.main.url(forResource: "YouTubeScriptlets", withExtension: nil) else {
            throw FilterError.conversion("Bundled scriptlet runtime missing")
        }
        let metadata = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: directory.appendingPathComponent("runtime.json")))
        let compressed = try Data(contentsOf: directory.appendingPathComponent("Scriptlets-2.3.1.js.lzfse"))
        let data = try (compressed as NSData).decompressed(using: .lzfse) as Data
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard metadata["version"] == version, metadata["sha256"] == hash,
              let source = String(data: data, encoding: .utf8), source.hasSuffix("export { scriptlets };\n") else {
            throw FilterError.conversion("Pinned scriptlet runtime failed integrity check")
        }
        // The official dependency-free ESM catalog is enclosed in our private IIFE.
        return String(source.dropLast("export { scriptlets };\n".count))
    }

    static func source(runtime: String, plans: [String: [YouTubeRuleAdapter.Call]]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let plan = String(decoding: try encoder.encode(plans), as: UTF8.self)
        return """
        (() => {
          'use strict';
          const host = location.hostname.toLowerCase();
          if (window !== window.top || !(host === 'youtube.com' || host.endsWith('.youtube.com'))) return;
          const plans = \(plan);
          if (!Object.hasOwn(plans, host)) return;
          \(runtime)
          const ran = [], failed = [];
          for (const call of plans[host]) {
            try {
              const fn = scriptlets.getScriptletFunction(call.runtimeName);
              if (typeof fn !== 'function') throw new Error('Unsupported scriptlet');
              fn({name:call.runtimeName,args:call.args,engine:'iris',version:'2.3.1',domainName:host,verbose:false,
                  uniqueId:'iris-youtube-' + JSON.stringify(call)}, call.args);
              ran.push(call.name + ' → ' + call.runtimeName);
            } catch (error) { failed.push(call.name); }
          }
          console.info('[Iris YouTube] runtime=2.3.1 page=' + location.href + ' invoked=' + ran.join(', ') + ' failed=' + failed.join(', '));
          window.webkit?.messageHandlers?.irisYouTubeScriptlets?.postMessage({version:'2.3.1',ran,failed});
        })();
        """
    }
}
