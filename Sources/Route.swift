import Foundation

/// Which maps app Route opens.
enum MapsApp: String, Codable, CaseIterable {
    case automatic, apple, google, waze, kurviger

    var name: String {
        switch self {
        case .automatic: return "Automatic"
        case .apple: return "Apple Maps"
        case .google: return "Google Maps"
        case .waze: return "Waze"
        case .kurviger: return "Kurviger"
        }
    }

    /// Apple Maps and Waze links only hold one place, so a route with stops goes to the first one.
    var holdsStops: Bool { self == .google || self == .kurviger }
}

/// Directions for a ride. A route the organiser shared in the description wins. Otherwise it's from home
/// (the rough spot of your suburb) to the meeting place, any stops, and the destination, read from labelled
/// lines like "Meet point: …", "Stop: …" or "Destination: …".
enum Route {
    struct Stops: Equatable {
        var meet: String?
        var via: [String] = []
        var destination: String?
    }

    /// A directions link in the text: Google Maps or Apple Maps. Short Google links can be a single place,
    /// so they only count on a line that mentions a route or directions.
    static func link(in text: String) -> String? {
        let full = #"https?://(?:www\.|maps\.)?google\.[a-z.]+/maps/dir/[^\s<>"]+|https?://maps\.apple\.com/[^\s<>"]*[?&](?:daddr|destination)=[^\s<>"]+"#
        let short = #"https?://(?:maps\.app\.goo\.gl|goo\.gl/maps)/[^\s<>"]+"#
        for line in text.components(separatedBy: .newlines) {
            if let l = first(full, in: line) { return l }
            if line.range(of: #"(?i)\b(route|directions|ride map|map of the ride)\b"#, options: .regularExpression) != nil,
               let l = first(short, in: line) { return l }
        }
        return nil
    }

    private static func first(_ pattern: String, in line: String) -> String? {
        guard let r = line.range(of: pattern, options: .regularExpression) else { return nil }
        return String(line[r]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]'"))
    }

    static func stops(in text: String) -> Stops {
        var s = Stops()
        let labels: [(kind: Int, pattern: String)] = [
            (0, #"meet(?:ing)?(?: up)?(?: point| spot| place| location)?|start(?:ing)?(?: point)?|kick ?stands? up(?: from)?|depart(?:ing|ure)?(?: from| point)?|leaving from"#),
            (1, #"stops?|via|regroup|fuel(?: stop)?|coffee(?: stop)?|lunch(?: stop)?|break|pit stop|waypoints?"#),
            (2, #"destination|finish(?:ing)?(?: point)?|end(?:ing)?(?: point)?|final stop|ride to|heading to"#),
        ]
        for raw in text.components(separatedBy: .newlines) {
            // Skip bullets and emoji before the label.
            let line = String(raw.drop { !$0.isLetter })
            for (kind, label) in labels {
                let p = #"(?i)^(?:"# + label + #")\s*\d*\s*[:\-–—]\s*(.+)$"#
                guard let re = try? NSRegularExpression(pattern: p),
                      let m = re.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                      let r = Range(m.range(at: 1), in: line) else { continue }
                let places = clean(String(line[r]), split: kind == 1)
                switch kind {
                case 0: if s.meet == nil { s.meet = places.first }
                case 1: s.via += places
                default: if s.destination == nil { s.destination = places.last }
                }
                break
            }
        }
        return s
    }

    /// "6:30pm at Shell Laverton" → "Shell Laverton"; stops can be listed as "A → B; C".
    private static func clean(_ value: String, split: Bool) -> [String] {
        var v = value.replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
        v = v.replacingOccurrences(of: #"(?i)^\s*\d{1,2}(?:[:.]\d{2})?\s*(?:am|pm)?\s*(?:at|@|from|-|–)?\s*"#, with: "",
                                   options: .regularExpression)
        let parts = split ? v.components(separatedBy: CharacterSet(charactersIn: "→;|")).flatMap { $0.components(separatedBy: "->") } : [v]
        return parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,"))) }
            .filter { $0.count >= 3 && $0.rangeOfCharacter(from: .letters) != nil }
    }

    /// The places in order, without repeats next to each other.
    static func places(meetingPlace: String, notes: String) -> [String] {
        let s = stops(in: notes)
        var out: [String] = []
        for p in [s.meet ?? meetingPlace] + s.via + [s.destination ?? ""] where !p.isEmpty {
            if out.last?.lowercased() != p.lowercased() { out.append(p) }
        }
        return out
    }

    /// The places a ride's title and description suggest, before they're checked on the map: the meeting place
    /// (a labelled line, or the ride's location), any stops, and the destination from a labelled line, a phrase like
    /// "heading to Marysville" or "lunch at Warburton", or a title like "Yarra Glen to Sugarloaf" or "Ride to Lorne".
    static func guess(title: String, location: String, notes: String) -> [String] {
        let s = stops(in: notes)
        var start = s.meet ?? location
        var destination = s.destination ?? phraseDestination(notes)
        if let (from, to) = titlePlaces(title) {
            if start.isEmpty, let from { start = from }
            if destination == nil { destination = to }
        }
        var out: [String] = []
        for p in [start] + s.via + [destination ?? ""] where !p.isEmpty {
            if out.last?.lowercased() != p.lowercased() { out.append(p) }
        }
        return out
    }

    /// A place name: one to four capitalised words ("Sugarloaf Reservoir", "Mt Buller", "Lake Eildon").
    private static let placeName = #"([A-Z][\w'’.-]+(?:\s+(?:[A-Z][\w'’.-]+|of|the)){0,3})"#

    /// "…heading to Marysville…", "…lunch at Warburton…", "…finishing at Lake Eildon…"
    static func phraseDestination(_ text: String) -> String? {
        let lead = #"(?i:\b(?:ride|riding|run|cruise|cruising|heading|head|trip|blast|rolling|going)\s+(?:out\s+|up\s+|down\s+)?to|\b(?:finish(?:ing)?|end(?:ing)?|lunch|arriv(?:e|ing)|destination(?:\s+is)?)\s+(?:up\s+)?(?:at|in|is)?)\s+(?:the\s+)?"#
        guard let re = try? NSRegularExpression(pattern: lead + placeName),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 1), in: text) else { return nil }
        let name = String(text[r]).trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
        // Days and months start with capitals too.
        let notPlaces = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "The"]
        return notPlaces.contains(where: { name.hasPrefix($0) }) ? nil : name
    }

    /// "Yarra Glen to Sugarloaf Reservoir" → (Yarra Glen, Sugarloaf Reservoir); "Ride to Lorne" → (nil, Lorne).
    static func titlePlaces(_ title: String) -> (String?, String)? {
        guard let re = try? NSRegularExpression(pattern: "^" + placeName + #"\s+(?:to|→|->)\s+"# + placeName + #"\s*$"#),
              let m = re.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
              let a = Range(m.range(at: 1), in: title), let b = Range(m.range(at: 2), in: title) else { return nil }
        let from = String(title[a])
        let generic = ["Ride", "Run", "Trip", "Cruise", "Blast", "Rideout", "Ride out", "Day trip", "Breakfast run", "Coffee run"]
        return (generic.contains { $0.lowercased() == from.lowercased() } ? nil : from, String(title[b]))
    }

    /// Google Maps directions in the browser, with every stop. Without a start it begins wherever you are.
    static func googleMaps(from origin: String?, through places: [String]) -> String? {
        guard let destination = places.last else { return nil }
        var c = URLComponents(string: "https://www.google.com/maps/dir/")!
        var q = [URLQueryItem(name: "api", value: "1")]
        if let origin { q.append(URLQueryItem(name: "origin", value: origin)) }
        q.append(URLQueryItem(name: "destination", value: destination))
        if places.count > 1 { q.append(URLQueryItem(name: "waypoints", value: places.dropLast().joined(separator: "|"))) }
        q.append(URLQueryItem(name: "travelmode", value: "driving"))
        c.queryItems = q
        c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "|", with: "%7C")
        return c.string
    }

    /// Kurviger's motorbike route planner in the browser, through every point (latitude, longitude) in order.
    /// Its links take map points rather than place names, so the places are found with Apple Maps first.
    static func kurviger(through points: [(latitude: Double, longitude: Double)]) -> String? {
        guard points.count >= 2 else { return nil }
        var c = URLComponents(string: "https://kurviger.de/")!
        c.queryItems = points.map { URLQueryItem(name: "point", value: String(format: "%.5f,%.5f", $0.latitude, $0.longitude)) }
        return c.string
    }

    /// Waze, driving to one place (in the app if it's installed, otherwise its website).
    static func waze(to place: String) -> String {
        var c = URLComponents(string: "https://waze.com/ul")!
        c.queryItems = [URLQueryItem(name: "q", value: place), URLQueryItem(name: "navigate", value: "yes")]
        return c.string ?? "https://waze.com/ul"
    }

    /// Apple Maps directions, for a route with no stops in between (its links can't carry them).
    static func appleMaps(from origin: String?, to place: String) -> String {
        var c = URLComponents(string: "maps://")!
        c.queryItems = (origin.map { [URLQueryItem(name: "saddr", value: $0)] } ?? [])
            + [URLQueryItem(name: "daddr", value: place), URLQueryItem(name: "dirflg", value: "d")]
        return c.string ?? "maps://"
    }
}

extension Store {
    /// The places a ride's route goes through. Labelled lines in its details win (they're what you typed with
    /// Edit…, or what the organiser wrote); otherwise the route RollCall found and checked. A ride at one place
    /// (a track day, a bike night) is the trip there from your suburb.
    func routePlaces(_ ride: RideEvent) -> [String] {
        let written = Route.places(meetingPlace: ride.location, notes: ride.notes)
        if written.count >= 2 { return written }
        let found = state.foundRoutes[ride.id].flatMap { $0.from == Route.fingerprint(ride) ? $0.places : nil } ?? []
        if found.count >= 2 { return found }
        guard let venue = found.first ?? written.first else { return [] }
        return [homePlace, venue]
    }

    /// Your suburb, as a place to plan from (never your street).
    var homePlace: String { state.settings.homeCity.flatMap { $0.isEmpty ? nil : $0 } ?? state.settings.homeName }
}

extension Route {
    /// What a found route was worked out from, so it's worked out again when the ride's details change.
    static func fingerprint(_ ride: RideEvent) -> String { stableHash(ride.title + "\n" + ride.location + "\n" + ride.notes) }
}
