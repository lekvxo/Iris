import Foundation
import OSLog

struct BlockedNavigation: Equatable {
    let url: URL
    let sourceSite: String
    let popup: Bool
}

struct NavigationGuard {
    let suffix: PublicSuffix
    private static let logger = Logger(subsystem: "com.max.iris", category: "NavigationGuard")
    static let signInHosts: Set<String> = ["accounts.google.com", "appleid.apple.com", "login.microsoftonline.com", "github.com"]

    struct Request {
        let destination: URL
        let current: URL?
        var mainFrame = true
        var popup = false
        var linkActivated = false
        var native = false
        var historyOrReload = false
        var form = false
        var serverRedirect = false
        var clickedLink: URL?
        var gestureAge: TimeInterval = .infinity
        var allowedSites: Set<String> = []
    }

    func allows(_ request: Request) -> Bool {
        guard ["http", "https"].contains(request.destination.scheme?.lowercased() ?? ""),
              let target = request.destination.host?.lowercased() else {
            return deny(request, reason: "unsupported URL scheme or missing host")
        }
        if request.native { return true }
        let sourceSite = request.current?.host.map(suffix.registrableDomain) ?? ""
        let sameSite = !sourceSite.isEmpty && suffix.registrableDomain(target) == sourceSite
        // An iframe must never use a main-frame gesture or sign-in exception.
        if !request.mainFrame {
            if !request.popup && sameSite { return true }
            return deny(request, reason: request.popup ? "subframe popup" : "subframe cross-site navigation")
        }
        if request.allowedSites.contains(sourceSite) { return true }
        let recentGesture = request.gestureAge >= 0 && request.gestureAge <= 2
        let matchingClick = recentGesture && request.clickedLink?.host?.lowercased() == target
        // Sign-in buttons open their provider with window.open: a real tap, but no link.
        if request.popup {
            if (request.linkActivated && matchingClick) || (recentGesture && Self.signInHosts.contains(target)) { return true }
            return deny(request, reason: "popup has no matching tapped link or recent sign-in gesture")
        }
        if sameSite || request.historyOrReload || request.form || request.serverRedirect ||
            matchingClick || Self.signInHosts.contains(target) { return true }
        return deny(request, reason: "cross-site navigation has no matching tapped link or exception")
    }

    private func deny(_ request: Request, reason: String) -> Bool {
        let kind = request.popup ? "popup" : "redirect"
        let source = request.current?.absoluteString ?? "(no source page)"
        Self.logger.notice("Blocked \(kind, privacy: .public): url=\(request.destination.absoluteString, privacy: .public) source=\(source, privacy: .public) reason=\(reason, privacy: .public)")
        return false
    }
}
