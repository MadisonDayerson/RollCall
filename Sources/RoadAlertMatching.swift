import Foundation
import CoreLocation

/// Which alerts are on a ride's route while you'd be riding it, grouped by road, most disruptive first. Worked
/// out on the Mac, so the route itself never goes online.
extension RoadAlerts {
    /// Closures first, then lanes blocked, then the rest; happening now before booked.
    static func rank(_ a: Alert) -> Int {
        let impact = a.closesRoad ? 0 : a.impact.localizedCaseInsensitiveContains("blocked") ? 1 : 2
        return impact * 2 + (a.planned ? 1 : 0)
    }

    /// The alerts grouped by road, most disruptive first.
    static func byRoad(_ alerts: [Alert]) -> [Road] {
        var roads: [Road] = []
        for a in alerts {
            // Ramps run beside the freeway, so every one you pass is near the route: they're shown together.
            let name = a.road.isEmpty || a.road == "Unnamed" ? "Unnamed road"
                : a.road.localizedCaseInsensitiveContains(" ramp") ? "On and off ramps" : a.road
            if let i = roads.firstIndex(where: { $0.name == name }) {
                roads[i].alerts.append(a)
                if !a.place.isEmpty, !roads[i].places.contains(a.place) { roads[i].places.append(a.place) }
            } else {
                roads.append(Road(name: name, places: a.place.isEmpty ? [] : [a.place], alerts: [a]))
            }
        }
        func rank(_ r: Road) -> Int { r.alerts.map(RoadAlerts.rank).min() ?? 9 }
        return roads.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
    }

    /// The alerts on the route that matter while you're riding it, from `from` to `to`: booked works on at that
    /// time, and alerts happening now if the ride is within a day.
    static func on(_ route: [CLLocationCoordinate2D], from: Date, to: Date, alerts: [Alert], now: Date = Date()) -> [Alert] {
        guard let first = route.first else { return [] }
        let live = from.timeIntervalSince(now) < liveHours * 3600 && to > now
        let margin = nearMetres / 111_000
        let south = route.map(\.latitude).min()! - margin, north = route.map(\.latitude).max()! + margin
        let west = route.map(\.longitude).min()! - margin * 1.3, east = route.map(\.longitude).max()! + margin * 1.3
        let scale = cos(first.latitude * .pi / 180)
        func xy(_ c: CLLocationCoordinate2D) -> (Double, Double) { (c.longitude * 111_320 * scale, c.latitude * 110_540) }
        let line = route.map(xy)
        func near(_ c: CLLocationCoordinate2D) -> Bool {
            guard (south...north).contains(c.latitude), (west...east).contains(c.longitude) else { return false }
            let p = xy(c)
            if line.count == 1 { return hypot(p.0 - line[0].0, p.1 - line[0].1) <= nearMetres }
            return zip(line, line.dropFirst()).contains { a, b in distance(p, a, b) <= nearMetres }
        }
        /// How far apart the furthest of these spots are, roughly.
        func span(_ spots: [CLLocationCoordinate2D]) -> Double {
            guard let s = spots.map(\.latitude).min(), let n = spots.map(\.latitude).max(),
                  let w = spots.map(\.longitude).min(), let e = spots.map(\.longitude).max() else { return 0 }
            return hypot((e - w) * 111_320 * scale, (n - s) * 110_540)
        }
        /// The alert's line with a spot every 25 m, so a long straight stretch has spots along its middle too.
        func filled(_ spots: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
            guard let last = spots.last else { return [] }
            return zip(spots, spots.dropFirst()).flatMap { a, b -> [CLLocationCoordinate2D] in
                let (p, q) = (xy(a), xy(b))
                let steps = min(400, max(1, Int(hypot(q.0 - p.0, q.1 - p.1) / 25)))
                return (0..<steps).map { i in
                    let t = Double(i) / Double(steps)
                    return CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * t,
                                                  longitude: a.longitude + (b.longitude - a.longitude) * t)
                }
            } + [last]
        }
        return alerts.compactMap { a in
            guard a.planned ? isOn(a, from: from, to: to) : live,
                  a.spots.map(\.latitude).max()! >= south, a.spots.map(\.latitude).min()! <= north,
                  a.spots.map(\.longitude).max()! >= west, a.spots.map(\.longitude).min()! <= east else { return nil }
            let close = filled(a.spots).filter(near)
            guard !close.isEmpty, span(close) >= min(alongMetres, span(a.spots) * 0.8) else { return nil }
            var matched = a
            matched.mark = close[close.count / 2]
            return matched
        }
    }

    /// Whether booked works are on at some point between `from` and `to`.
    static func isOn(_ a: Alert, from: Date, to: Date) -> Bool {
        guard (a.start ?? .distantPast) < to, (a.end ?? .distantFuture) > from else { return false }
        guard !a.times.isEmpty else { return true }
        var day = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: from)) ?? from
        while day < to {
            let weekday = calendar.component(.weekday, from: day)
            for t in a.times where t.weekday == weekday {
                let s = day.addingTimeInterval(Double(t.minutes) * 60)
                if s < to, s.addingTimeInterval(t.seconds) > from { return true }
            }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? to
        }
        return false
    }

    /// When you're out on the ride, roughly: from when you'd leave until the ride ends or you'd have ridden the
    /// route. A ride without a time is taken to leave at 9 am, as for the weather.
    static func riding(_ ride: RideEvent, seconds: Double, arriving: Bool) -> (from: Date, to: Date) {
        let leave = RouteWeather.leave(ride, seconds: seconds, arriving: arriving)
        let ridden = leave.addingTimeInterval(seconds)
        return ride.allDay ? (leave, ridden) : (min(leave, ride.start), max(ride.finish, ridden))
    }

    /// How far point p is from the segment a–b, in metres.
    private static func distance(_ p: (Double, Double), _ a: (Double, Double), _ b: (Double, Double)) -> Double {
        let dx = b.0 - a.0, dy = b.1 - a.1
        let length = dx * dx + dy * dy
        let t = length == 0 ? 0 : max(0, min(1, ((p.0 - a.0) * dx + (p.1 - a.1) * dy) / length))
        return hypot(p.0 - (a.0 + t * dx), p.1 - (a.1 + t * dy))
    }
}
