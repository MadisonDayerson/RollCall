import Foundation

/// Which rides are on which days, for the week and month views.
enum RideCalendar {
    enum Span { case week, month }

    /// The days a ride is on, as the start of each. One that runs past midnight counts on the day it starts, unless
    /// it's all day or lasts a day or more, like a weekend away.
    static func days(_ ride: RideEvent, in calendar: Calendar = .current) -> [Date] {
        let first = calendar.startOfDay(for: ride.start)
        guard ride.allDay || ride.finish.timeIntervalSince(ride.start) >= 86400 else { return [first] }
        var days = [first]
        while let next = calendar.date(byAdding: .day, value: 1, to: days.last!), next < ride.finish { days.append(next) }
        return days
    }

    static func byDay(_ rides: [RideEvent], in calendar: Calendar = .current) -> [Date: [RideEvent]] {
        var out: [Date: [RideEvent]] = [:]
        for ride in rides { for day in days(ride, in: calendar) { out[day, default: []].append(ride) } }
        return out
    }

    /// The day's week, or every day of its month.
    static func days(of span: Span, at day: Date, in calendar: Calendar = .current) -> [Date] {
        guard let range = calendar.dateInterval(of: span == .week ? .weekOfYear : .month, for: day) else { return [] }
        var days = [range.start]
        while let next = calendar.date(byAdding: .day, value: 1, to: days.last!), next < range.end { days.append(next) }
        return days
    }

    /// The week, or the month in whole weeks with nil for days outside it.
    static func grid(of span: Span, at day: Date, in calendar: Calendar = .current) -> [[Date?]] {
        let days = days(of: span, at: day, in: calendar)
        guard let first = days.first else { return [] }
        let before = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        var cells = Array(repeating: Date?.none, count: before) + days
        cells += Array(repeating: nil, count: (7 - cells.count % 7) % 7)
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    /// The same day in the week or month before or after.
    static func move(_ day: Date, by n: Int, _ span: Span, in calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: span == .week ? .weekOfYear : .month, value: n, to: day) ?? day
    }
}
