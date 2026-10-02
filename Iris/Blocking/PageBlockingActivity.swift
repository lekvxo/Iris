import Foundation

// Presentation data only: existing guard decisions remain the source of truth.
struct PageBlockingActivity {
    enum Kind: String, Hashable { case popup, redirect }
    struct Item: Identifiable, Hashable {
        let url: URL
        let kind: Kind
        var id: Self { self }
        var title: String { kind == .popup ? "Popup" : "Redirect" }
        var symbol: String { kind == .popup ? "macwindow.on.rectangle" : "arrow.turn.up.right" }
    }

    static let detailLimit = 200
    private(set) var pageID = UUID()
    private(set) var items: [Item] = []
    private(set) var hasMore = false
    private var recorded: Set<Item> = []

    var count: Int { items.count }
    var badgeTitle: String { count.formatted() + (hasMore ? "+" : "") }
    var summary: String {
        if hasMore { return "Blocked \(badgeTitle) unwanted destinations" }
        let popups = items.filter { $0.kind == .popup }.count
        let redirects = count - popups
        var parts: [String] = []
        if popups > 0 { parts.append("\(popups.formatted()) \(popups == 1 ? "popup" : "popups")") }
        if redirects > 0 { parts.append("\(redirects.formatted()) \(redirects == 1 ? "redirect" : "redirects")") }
        return parts.isEmpty ? "No popups or redirects blocked on this page" : "Blocked " + parts.joined(separator: " and ")
    }

    mutating func record(_ url: URL, kind: Kind) {
        let item = Item(url: url, kind: kind)
        // The reporting script and native delegate can report the same popup.
        // Count each destination once, and bound memory on aggressive pages.
        guard !recorded.contains(item) else { return }
        guard items.count < Self.detailLimit else { hasMore = true; return }
        recorded.insert(item)
        items.append(item)
    }

    mutating func reset() { self = Self() }
}
