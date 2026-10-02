import Foundation

enum HistoryClearRange: String, CaseIterable, Identifiable {
    case hour, today, todayAndYesterday, all
    var id: String { rawValue }
    var title: String {
        switch self {
        case .hour: "Last hour"
        case .today: "Today"
        case .todayAndYesterday: "Today and yesterday"
        case .all: "All history"
        }
    }

    func start(now: Date, calendar: Calendar) -> Date? {
        switch self {
        case .hour: now.addingTimeInterval(-3600)
        case .today: calendar.startOfDay(for: now)
        case .todayAndYesterday: calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))
        case .all: nil
        }
    }
}

enum HistoryRetention: String, CaseIterable, Identifiable {
    case month, year, forever
    var id: String { rawValue }
    var title: String {
        switch self {
        case .month: "1 month"
        case .year: "1 year"
        case .forever: "Forever"
        }
    }

    func cutoff(now: Date, calendar: Calendar) -> Date? {
        switch self {
        case .month: calendar.date(byAdding: .month, value: -1, to: now)
        case .year: calendar.date(byAdding: .year, value: -1, to: now)
        case .forever: nil
        }
    }
}
