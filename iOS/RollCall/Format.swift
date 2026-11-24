import Foundation

/// How a ride's day, time and place are written: "Sunday 7 December, 8:30 am".
enum Format {
    private static func fmt(_ pattern: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_AU")
        f.dateFormat = pattern
        f.amSymbol = "am"
        f.pmSymbol = "pm"
        return f
    }
    static let day = fmt("EEEE d MMMM"), time = fmt("h:mm a")
    private static let month = fmt("MMMM yyyy"), dayMonth = fmt("d MMM")

    /// "November 2026", or a week as "23 – 29 Nov".
    static func span(_ span: RideCalendar.Span, at day: Date) -> String {
        let days = RideCalendar.days(of: span, at: day)
        guard span == .week, let first = days.first, let last = days.last else { return month.string(from: day) }
        let sameMonth = Calendar.current.isDate(first, equalTo: last, toGranularity: .month)
        return "\((sameMonth ? DateBadge.day : dayMonth).string(from: first)) – \(dayMonth.string(from: last))"
    }

    /// How long until a ride: "Today", "Tomorrow", "In 5 days".
    static func until(_ ride: RideEvent, now: Date = Date()) -> String {
        if ride.start <= now, !ride.allDay { return "On now" }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: ride.start)).day ?? 0
        switch days {
        case ..<0: return "On now"
        case 0: return "Today"
        case 1: return "Tomorrow"
        case 2..<14: return "In \(days) days"
        default: return "In \(days / 7) weeks"
        }
    }

    static func when(_ ride: RideEvent) -> String {
        ride.allDay ? "\(day.string(from: ride.start)), all day" : "\(day.string(from: ride.start)), \(time.string(from: ride.start))"
    }

    static func place(_ ride: RideEvent) -> String? {
        let km = ride.distanceKm.map { "\(Int($0.rounded())) km away" }
        let parts = [ride.location.isEmpty ? nil : ride.location, km].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
