import Foundation
import SwiftData

@Model
final class SavedSite {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var url: String
    var title: String
    var note: String
    var createdAt: Date
    var lastOpened: Date?
    var archiveFileName: String?

    init(url: URL, title: String, note: String = "") {
        id = UUID()
        self.url = url.absoluteString
        self.title = title
        self.note = note
        createdAt = Date()
    }
}
