import MapKit

/// Plans a ride's road route with Apple Maps: the meeting place, any stops and the destination, found near
/// home and joined by driving directions. Free, no account, and kept in memory only.
@MainActor
enum RoutePlanner {
    struct Planned {
        /// The road route, one line per leg.
        var legs: [MKPolyline]
        /// Where each place was found, in order: start, stops, finish.
        var stops: [CLLocationCoordinate2D]
        /// Which stops are named places; the rest are map points a route link was dragged through, not stops.
        var named: [Bool]
        var metres: Double
        var seconds: Double

        /// Tells one route from another, so a map is drawn afresh when the route changes.
        var key: String { stops.map { "\($0.latitude),\($0.longitude)" }.joined(separator: ";") + "|\(metres)" }

        /// The whole road route as one line of spots.
        var line: [CLLocationCoordinate2D] {
            legs.flatMap { leg in let p = leg.points(); return (0..<leg.pointCount).map { p[$0].coordinate } }
        }

        /// The part of the map that shows the whole route in a map this size, with room around it for the marks.
        func mapRect(size: CGSize) -> MKMapRect {
            var rect = legs.map(\.boundingMapRect).reduce(MKMapRect.null) { $0.union($1) }
            rect = rect.insetBy(dx: -rect.width * 0.1 - 1, dy: -rect.height * 0.1 - 1)
            // Widen the short side to the map's shape, so MapKit doesn't crop the route to fit.
            let aspect = size.width / size.height
            if rect.width / rect.height < aspect {
                return rect.insetBy(dx: -(rect.height * aspect - rect.width) / 2, dy: 0)
            }
            return rect.insetBy(dx: 0, dy: -(rect.width / aspect - rect.height) / 2)
        }
    }

    // Only what was found is remembered, so a place missed while offline is tried again next time.
    private static var routes: [String: Planned] = [:]
    private static var found: [String: CLLocationCoordinate2D] = [:]

    /// The route through the places, or nil when there aren't two places or one couldn't be found.
    static func plan(_ places: [String], near home: CLLocationCoordinate2D, avoidHighways: Bool = false) async -> Planned? {
        guard places.count >= 2 else { return nil }
        let key = places.joined(separator: "\n").lowercased() + (avoidHighways ? "|no highways" : "")
        if let cached = routes[key] { return cached }
        var result: Planned?
        if let points = await locate(places, near: home) {
            var planned = Planned(legs: [], stops: points, named: places.map { Route.point($0) == nil }, metres: 0, seconds: 0)
            for (a, b) in zip(points, points.dropFirst()) {
                guard let leg = await drive(from: a, to: b, avoidHighways: avoidHighways) else { planned.legs = []; break }
                planned.legs.append(leg.polyline)
                planned.metres += leg.distance
                planned.seconds += leg.expectedTravelTime
            }
            if !planned.legs.isEmpty { result = planned }
        }
        routes[key] = result
        return result
    }

    /// Each place's spot, or nil if any can't be found.
    static func locate(_ places: [String], near home: CLLocationCoordinate2D) async -> [CLLocationCoordinate2D]? {
        var points: [CLLocationCoordinate2D] = []
        for place in places {
            guard let p = await locate(place, near: home) else { return nil }
            points.append(p)
        }
        return points
    }

    /// `within` is how wide an area (in metres) the search favours around `home`.
    static func locate(_ place: String, near home: CLLocationCoordinate2D, within: Double = 600_000) async -> CLLocationCoordinate2D? {
        // A map point from a route link needs no looking up.
        if let p = Route.point(place) { return CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude) }
        let key = "\(place.lowercased())|\(Int(home.latitude * 10)),\(Int(home.longitude * 10))|\(Int(within))"
        if let cached = found[key] { return cached }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = place
        // Places in the rider's part of the world first: "Shell Coldstream", not one overseas.
        request.region = MKCoordinateRegion(center: home, latitudinalMeters: within, longitudinalMeters: within)
        let spot = try? await MKLocalSearch(request: request).start().mapItems.first?.spot
        found[key] = spot
        return spot
    }

    private static func drive(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D, avoidHighways: Bool) async -> MKRoute? {
        let request = MKDirections.Request()
        request.source = MKMapItem.at(a)
        request.destination = MKMapItem.at(b)
        request.transportType = .automobile
        if avoidHighways { request.highwayPreference = .avoid }
        return try? await MKDirections(request: request).calculate().routes.first
    }

    /// "123 km · about 2 h 10 min riding · Frankston → Healesville", or "the organiser's route" for a route link.
    /// `arriving` is a ride at one place, with the way there from your suburb.
    static func describe(_ p: Planned, places: [String], notes: String, arriving: Bool) -> String {
        let km = Int((p.metres / 1000).rounded())
        let minutes = Int((p.seconds / 60 / 5).rounded()) * 5
        let time = minutes >= 60 ? "\(minutes / 60) h" + (minutes % 60 > 0 ? " \(minutes % 60) min" : "") : "\(max(minutes, 5)) min"
        // A route link's stops are map points, so it's described rather than listed.
        let through = Route.link(in: notes) != nil && places.contains { Route.point($0) != nil } ? "the organiser's route" : places.joined(separator: " → ")
        let undecided = arriving ? Route.decidedLater(notes).map { " · \($0)" } ?? "" : ""
        return "\(km) km · about \(time) riding · \(through)\(undecided)"
    }
}
