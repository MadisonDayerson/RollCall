import MapKit

/// Works out a new ride's start, stops and destination so its route map can be drawn: first from its title and
/// description, then (when that doesn't give two places Apple Maps can find) by asking Apple Intelligence on the
/// Mac to read the description. Every place is checked with Apple Maps, and ones it can't find, or that are far
/// from home, are left out. A ride at one place gets the route there from your suburb (see `Store.routePlaces`).
@MainActor
enum RouteFinder {
    /// Places further than this from home are a wrong match (another state's "Kinglake"), not a ride stop.
    static let maxKmFromHome = 400.0
    /// A "route" that stays within a few kilometres is one venue (a bike night at the waterfront), not a ride.
    static let minKmSpan = 3.0
    /// A meeting place this far from the ride's own location is a wrong match ("Customs Lawn" found in Melbourne
    /// for a Geelong event), so the location is used instead.
    static let maxKmStartFromLocation = 25.0

    static func find(_ ride: RideEvent, home: CLLocationCoordinate2D) async -> [String] {
        // A short maps.app.goo.gl link hides the organiser's route: follow it to the full link once.
        if let link = Route.link(in: ride.notes), Route.linkPlaces(link).count < 2,
           let full = await expand(link), Route.linkPlaces(full).count >= 2 {
            return Route.linkPlaces(full)
        }
        let guessed = await checked(Route.guess(title: ride.title, location: ride.location, notes: ride.notes), ride: ride, home: home)
        if guessed.count >= 2 || !AppleModel.available || ride.notes.isEmpty { return guessed }
        let text = [ride.title, ride.location.isEmpty ? "" : "Location: " + ride.location, ride.notes]
            .filter { !$0.isEmpty }.joined(separator: "\n")
        guard let d = await RideDetails.extract(RideDetails.input(post: text)) else { return guessed }
        let read = await checked([d.meet ?? ride.location] + d.stops + [d.destination ?? ""], ride: ride, home: home)
        return read.count > guessed.count ? read : guessed
    }

    /// Where a short link leads, without cookies (see `Net`).
    static func expand(_ link: String) async -> String? {
        guard let url = URL(string: link) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(Web.userAgent, forHTTPHeaderField: "User-Agent")
        return try? await Net.session.data(for: request).1.url?.absoluteString
    }

    /// The places Apple Maps can find near home, in order, without repeats of the same spot. Fewer than two
    /// means the ride is at one place.
    static func checked(_ places: [String], ride: RideEvent, home: CLLocationCoordinate2D) async -> [String] {
        func km(_ c: CLLocationCoordinate2D, _ d: CLLocationCoordinate2D) -> Double { Store.haversineKm(c.latitude, c.longitude, d.latitude, d.longitude) }
        let location = ride.location.isEmpty ? nil : await RoutePlanner.locate(ride.location, near: home)
        var out: [(name: String, spot: CLLocationCoordinate2D)] = []
        for (i, place) in places.enumerated() where !place.trimmingCharacters(in: .whitespaces).isEmpty {
            guard var spot = await RoutePlanner.locate(place, near: location ?? home), km(spot, home) <= maxKmFromHome else { continue }
            var name = place
            if i == 0, let location, km(spot, location) > maxKmStartFromLocation { (name, spot) = (ride.location, location) }
            if let last = out.last, km(last.spot, spot) < 0.5 { continue }
            out.append((name, spot))
        }
        guard let first = out.first else { return [] }
        let span = out.map { km(first.spot, $0.spot) }.max() ?? 0
        return span < minKmSpan ? [first.name] : out.map(\.name)
    }
}
