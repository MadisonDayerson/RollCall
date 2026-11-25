import MapKit

/// Looking places up with Apple Maps. macOS and iOS 26 have a new way; macOS 14 and 15 only have the old one, which
/// gives the state by itself. Both are kept here, so nothing else needs to know which is used.
@MainActor
enum Places {
    struct Found {
        var spot: CLLocationCoordinate2D
        var city: String?
        var state: String?
        var country: String?
        /// "AU"
        var countryCode: String?
    }

    /// The places an address or a name might mean, best first. `home` is favoured when it's given.
    static func find(_ text: String, near home: CLLocationCoordinate2D? = nil, within metres: Double = 300_000) async throws -> [Found] {
        if #available(macOS 26, iOS 26, *) {
            guard let request = MKGeocodingRequest(addressString: text) else { return [] }
            if let home { request.region = MKCoordinateRegion(center: home, latitudinalMeters: metres * 2, longitudinalMeters: metres * 2) }
            return try await request.mapItems.map { item in
                let a = item.addressRepresentations
                return Found(spot: item.spot, city: a?.cityName, state: state(in: item.address?.fullAddress ?? "", city: a?.cityName) ?? a?.cityName,
                             country: a?.regionName, countryCode: a?.region?.identifier)
            }
        } else {
            let region = home.map { CLCircularRegion(center: $0, radius: metres, identifier: "home") }
            return try await CLGeocoder().geocodeAddressString(text, in: region).compactMap { m in
                guard let spot = m.location?.coordinate else { return nil }
                return Found(spot: spot, city: m.locality ?? m.subAdministrativeArea, state: m.administrativeArea,
                             country: m.country, countryCode: m.isoCountryCode)
            }
        }
    }

    /// A home area, preferring matches in the device's own country (so "Ringwood" is the Victorian one here).
    static func home(_ text: String) async throws -> Found? {
        let found = try await find(text)
        let here = Locale.current.region?.identifier
        return found.first { $0.countryCode == here } ?? found.first
    }

    /// The suburb or town a spot is in.
    static func suburb(at spot: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: spot.latitude, longitude: spot.longitude)
        if #available(macOS 26, iOS 26, *) {
            return try? await MKReverseGeocodingRequest(location: location)?.mapItems.first?.addressRepresentations?.cityName
        } else {
            let mark = try? await CLGeocoder().reverseGeocodeLocation(location).first
            return mark?.locality ?? mark?.subAdministrativeArea
        }
    }

    /// The state in a full address, which the new way doesn't give by itself: "VIC" in "Ringwood VIC 3134, Australia"
    /// and "CA" in "Cupertino, CA 95014, United States". Nil for countries whose addresses have none.
    nonisolated static func state(in address: String, city: String?) -> String? {
        // A full address can come on several lines; its country is last.
        let parts = address.components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard parts.count >= 2 else { return nil }
        var line = parts[parts.count - 2]
        if let city, line.hasPrefix(city) { line.removeFirst(city.count) }
        let words = line.split(separator: " ").filter { !$0.contains(where: \.isNumber) }
        return words.isEmpty ? nil : words.joined(separator: " ")
    }
}

extension MKMapItem {
    var spot: CLLocationCoordinate2D {
        if #available(macOS 26, iOS 26, *) { return location.coordinate } else { return placemark.coordinate }
    }

    static func at(_ spot: CLLocationCoordinate2D) -> MKMapItem {
        if #available(macOS 26, iOS 26, *) {
            return MKMapItem(location: CLLocation(latitude: spot.latitude, longitude: spot.longitude), address: nil)
        } else {
            return MKMapItem(placemark: MKPlacemark(coordinate: spot))
        }
    }
}
