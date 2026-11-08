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
        let spot = try? await MKLocalSearch(request: request).start().mapItems.first?.placemark.coordinate
        found[key] = spot
        return spot
    }

    private static func drive(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D, avoidHighways: Bool) async -> MKRoute? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: a))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: b))
        request.transportType = .automobile
        if avoidHighways { request.highwayPreference = .avoid }
        return try? await MKDirections(request: request).calculate().routes.first
    }

    /// "123 km · about 2 h 10 min riding"
    static func describe(_ p: Planned) -> String {
        let km = Int((p.metres / 1000).rounded())
        let minutes = Int((p.seconds / 60 / 5).rounded()) * 5
        let time = minutes >= 60 ? "\(minutes / 60) h" + (minutes % 60 > 0 ? " \(minutes % 60) min" : "") : "\(max(minutes, 5)) min"
        return "\(km) km · about \(time) riding"
    }
}
