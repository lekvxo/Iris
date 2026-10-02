import Foundation
import SwiftData

@Model
final class HistoryEntry {
    #Index<HistoryEntry>([\.url, \.visitedAt], [\.visitedAt])
    var url: String
    var title: String
    var host: String
    var visitedAt: Date

    init(url: URL, title: String, visitedAt: Date = Date()) {
        self.url = url.absoluteString
        self.title = title
        host = url.host ?? ""
        self.visitedAt = visitedAt
    }
}
