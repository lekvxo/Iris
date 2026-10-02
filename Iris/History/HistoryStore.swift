import Foundation
import Observation
import SwiftData

@MainActor @Observable
final class HistoryStore {
    private let context: ModelContext
    private let calendar: Calendar
    private let now: () -> Date
    private(set) var error: String?

    init(context: ModelContext, calendar: Calendar = .autoupdatingCurrent, now: @escaping () -> Date = Date.init) {
        self.context = context
        self.calendar = calendar
        self.now = now
    }

    func record(url: URL, title: String) {
        guard Self.canRecord(url) else { return }
        perform {
            let visit = now()
            guard let day = calendar.dateInterval(of: .day, for: visit) else { return }
            let address = url.absoluteString
            let start = day.start, end = day.end
            var fetch = FetchDescriptor<HistoryEntry>(predicate: #Predicate {
                $0.url == address && $0.visitedAt >= start && $0.visitedAt < end
            })
            fetch.fetchLimit = 1
            let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if let entry = try context.fetch(fetch).first {
                entry.visitedAt = visit
                if !name.isEmpty { entry.title = name }
            } else {
                context.insert(HistoryEntry(url: url, title: name.isEmpty ? url.host ?? address : name, visitedAt: visit))
            }
            try context.save()
        }
    }

    // A delayed title must not recreate an entry that the user has just cleared.
    func updateLatestTitle(url: URL, title: String) {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.canRecord(url), !name.isEmpty else { return }
        perform {
            let address = url.absoluteString
            var fetch = FetchDescriptor<HistoryEntry>(predicate: #Predicate { $0.url == address },
                                                      sortBy: [SortDescriptor(\.visitedAt, order: .reverse)])
            fetch.fetchLimit = 1
            guard let entry = try context.fetch(fetch).first, entry.title != name else { return }
            entry.title = name
            try context.save()
        }
    }

    static func canRecord(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased()) && url.host?.isEmpty == false
    }

    static func fetchDescriptor(search: String = "") -> FetchDescriptor<HistoryEntry> {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        var fetch = FetchDescriptor<HistoryEntry>(sortBy: [SortDescriptor(\.visitedAt, order: .reverse)])
        if term.isEmpty {
            fetch.fetchLimit = 500
        } else {
            fetch.predicate = #Predicate {
                $0.title.localizedStandardContains(term) || $0.url.localizedStandardContains(term)
            }
        }
        return fetch
    }

    func delete(_ entry: HistoryEntry) {
        perform {
            context.delete(entry)
            try context.save()
        }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action(); error = nil }
        catch { self.error = error.localizedDescription }
    }
}
