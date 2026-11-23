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

    static func when(_ ride: RideEvent) -> String {
        ride.allDay ? "\(day.string(from: ride.start)), all day" : "\(day.string(from: ride.start)), \(time.string(from: ride.start))"
    }

    static func place(_ ride: RideEvent) -> String? {
        let km = ride.distanceKm.map { "\(Int($0.rounded())) km away" }
        let parts = [ride.location.isEmpty ? nil : ride.location, km].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
