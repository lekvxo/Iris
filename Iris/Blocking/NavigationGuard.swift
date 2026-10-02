import Foundation

struct BlockedNavigation: Equatable {
    let url: URL
    let sourceSite: String
    let popup: Bool
}

struct NavigationGuard {
    let suffix: PublicSuffix
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
              let target = request.destination.host?.lowercased() else { return false }
        if request.native { return true }
        let sourceSite = request.current?.host.map(suffix.registrableDomain) ?? ""
        let sameSite = !sourceSite.isEmpty && suffix.registrableDomain(target) == sourceSite
        // An iframe must never use a main-frame gesture or sign-in exception.
        if !request.mainFrame { return !request.popup && sameSite }
        if request.allowedSites.contains(sourceSite) { return true }
        let matchingClick = request.gestureAge >= 0 && request.gestureAge <= 2 &&
            request.clickedLink?.host?.lowercased() == target
        if request.popup { return request.linkActivated && matchingClick }
        return sameSite || request.historyOrReload || request.form || request.serverRedirect ||
            matchingClick || Self.signInHosts.contains(target)
    }
}
