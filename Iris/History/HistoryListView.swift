import SwiftData
import SwiftUI

struct HistoryListView: View {
    let open: (URL) -> Void
    @State private var search = ""

    var body: some View {
        HistoryResults(search: search, open: open)
            .searchable(text: $search, prompt: "Search history")
    }
}

private struct HistoryResults: View {
    let search: String
    let open: (URL) -> Void
    @Query private var entries: [HistoryEntry]
    @Environment(SettingsStore.self) private var settings
    @Environment(\.calendar) private var calendar

    init(search: String, open: @escaping (URL) -> Void) {
        self.search = search
        self.open = open
        _entries = Query(HistoryStore.fetchDescriptor(search: search))
    }

    var body: some View {
        List {
            if entries.isEmpty {
                Text(search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No history yet" : "No matching pages")
                    .foregroundStyle(.secondary)
            }
            ForEach(HistoryDay.sections(entries, calendar: calendar)) { day in
                Section(day.title) {
                    ForEach(day.entries) { entry in
                        Button {
                            if let url = URL(string: entry.url) { open(url) }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.title).lineLimit(1)
                                HStack {
                                    Text(entry.host).lineLimit(1)
                                    Spacer()
                                    Text(entry.visitedAt, format: .dateTime.hour().minute())
                                }.font(.caption).foregroundStyle(.secondary)
                            }
                        }.hoverEffect()
                            .contextMenu {
                                Button("Delete", systemImage: "trash", role: .destructive) { settings.history.delete(entry) }
                            }
                    }
                }
            }
            if let error = settings.history.error { Text(error).foregroundStyle(.red) }
        }
    }
}

struct HistoryDay: Identifiable {
    let id: Date
    let title: String
    var entries: [HistoryEntry]

    static func sections(_ entries: [HistoryEntry], calendar: Calendar = .autoupdatingCurrent, now: Date = Date()) -> [HistoryDay] {
        let today = calendar.startOfDay(for: now)
        var weekday = Date.FormatStyle.dateTime.weekday(.wide)
        weekday.calendar = calendar
        weekday.timeZone = calendar.timeZone
        var date = Date.FormatStyle.dateTime.year().month(.abbreviated).day()
        date.calendar = calendar
        date.timeZone = calendar.timeZone
        var sections: [HistoryDay] = []
        for entry in entries {
            let day = calendar.startOfDay(for: entry.visitedAt)
            if sections.last?.id == day {
                sections[sections.count - 1].entries.append(entry)
            } else {
                let age = calendar.dateComponents([.day], from: day, to: today).day ?? 0
                let title: String
                switch age {
                case 0: title = "Today"
                case 1: title = "Yesterday"
                case 2..<7: title = day.formatted(weekday)
                default: title = day.formatted(date)
                }
                sections.append(HistoryDay(id: day, title: title, entries: [entry]))
            }
        }
        return sections
    }
}
