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

    /// The route in a Google Maps or Apple Maps directions link, as places in order. Google's links name each stop
    /// in the path and keep their map points, with any points the route was dragged through, in `data=`; those
    /// points are used where they're there, so the map follows the organiser's roads. Points are "latitude,longitude".
    static func linkPlaces(_ link: String) -> [String] {
        guard let c = URLComponents(string: link) else { return [] }
        // Links write spaces as "+".
        let query = Dictionary((c.queryItems ?? []).compactMap { q in q.value.map { (q.name, $0.replacingOccurrences(of: "+", with: " ")) } },
                               uniquingKeysWith: { a, _ in a })
        if c.scheme == "maps" || c.host?.hasSuffix("apple.com") == true {
            return [query["saddr"], query["daddr"]].compactMap { $0 }.filter { !$0.isEmpty }
        }
        guard c.percentEncodedPath.contains("/maps/dir/") else { return [] }
        if query["api"] == "1" {
            let via = query["waypoints"].map { $0.components(separatedBy: "|") } ?? []
            return ([query["origin"]] + via + [query["destination"]]).compactMap { $0 }.filter { !$0.isEmpty }
        }
        let (stops, data) = pathStops(c)
        guard let steps = directions(data) else { return stops }
        // Each stop is its own spot when Google gives one (or the path's name or point when not), followed by
        // the points the route was dragged through on the way to the next stop.
        guard steps.stops.count == stops.count else { return stops }  // not the shape expected: the path is still right
        return zip(stops, steps.stops).flatMap { name, step in [step.spot ?? name] + step.via }
    }

    /// The organiser's Google route was planned avoiding motorways ("Avoid highways" in Google Maps).
    static func linkAvoidsHighways(_ link: String) -> Bool {
        guard let c = URLComponents(string: link), c.percentEncodedPath.contains("/maps/dir/") else { return false }
        return directions(pathStops(c).data)?.avoidHighways ?? false
    }

    /// The stops written in a /maps/dir/ path, and its `data=` part.
    private static func pathStops(_ c: URLComponents) -> (stops: [String], data: String) {
        guard let dir = c.percentEncodedPath.range(of: "/maps/dir/") else { return ([], "") }
        var stops: [String] = []
        for part in c.percentEncodedPath[dir.upperBound...].split(separator: "/") {
            if part.hasPrefix("data=") { return (stops, String(part.dropFirst(5))) }
            if part.hasPrefix("@") { continue }
            let name = (String(part).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String(part))
                .trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { stops.append(name) }
        }
        return (stops, "")
    }

    /// Google's `data=` is a nested list: "!1m5" opens a group of the next 5 items (groups inside it included).
    /// The directions are the group "!4m…!4m…". In it, each stop is a "!1m…" group: its own spot is
    /// "!2m2!1d<lng>!2d<lat>" (missing when the path gives the stop, as in "!1m0"), and each point the route was
    /// dragged through after it is a "!3m4!1m2!1d<lng>!2d<lat>…" group. The options group "!2m…" holds "!1b1"
    /// for avoiding highways.
    private static func directions(_ data: String) -> (stops: [(spot: String?, via: [String])], avoidHighways: Bool)? {
        let items = data.split(separator: "!").map(String.init)
        // "1m5" -> (field 1, 5 items in the group); "1d144.9" isn't a group.
        func group(_ item: String) -> (field: Int, size: Int)? {
            let parts = item.split(separator: "m", maxSplits: 1)
            guard parts.count == 2, let f = Int(parts[0]), let n = Int(parts[1]) else { return nil }
            return (f, n)
        }
        // The top-level items of a list, each with the items inside it.
        func children(_ list: ArraySlice<String>) -> [(item: String, inside: ArraySlice<String>)] {
            var out: [(String, ArraySlice<String>)] = [], i = list.startIndex
            while i < list.endIndex {
                let n = min(group(list[i])?.size ?? 0, list.endIndex - i - 1)
                out.append((list[i], list[(i + 1)..<(i + 1 + n)]))
                i += 1 + n
            }
            return out
        }
        func spot(_ list: ArraySlice<String>) -> String? {
            guard let lng = list.first(where: { $0.hasPrefix("1d") })?.dropFirst(2),
                  let lat = list.first(where: { $0.hasPrefix("2d") })?.dropFirst(2), Double(lng) != nil, Double(lat) != nil else { return nil }
            return "\(lat),\(lng)"
        }
        guard let start = items.indices.first(where: { i in
            group(items[i])?.field == 4 && i + 1 < items.count && group(items[i + 1])?.field == 4
        }) else { return nil }
        guard let route = children(items[(start + 1)...]).first?.inside else { return nil }
        var stops: [(spot: String?, via: [String])] = [], avoid = false
        for part in children(route) {
            switch group(part.item) {
            case (1, _)?:
                var stop: (spot: String?, via: [String]) = (nil, [])
                for inner in children(part.inside) {
                    if inner.item == "2m2" { stop.spot = spot(inner.inside) }
                    if group(inner.item)?.field == 3, let p = spot(inner.inside) { stop.via.append(p) }
                }
                stops.append(stop)
            case (2, _)?:
                avoid = part.inside.contains("1b1")
            default:
                break
            }
        }
        return (stops, avoid)
    }

    /// "-37.8810219,145.1634224" as a map point.
    static func point(_ place: String) -> (latitude: Double, longitude: Double)? {
        let parts = place.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2, let lat = parts[0], let lng = parts[1], abs(lat) <= 90, abs(lng) <= 180 else { return nil }
        return (lat, lng)
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
    /// The places a ride's route goes through. The organiser's Google or Apple Maps route link wins; then labelled
    /// lines in its details (what you typed with Edit…, or what the organiser wrote); then the route RollCall found
    /// and checked. A ride at one place (a track day, a bike night) is the trip there from your suburb.
    func routePlaces(_ ride: RideEvent) -> [String] { route(ride).places }

    /// The route's places, and whether the organiser planned it avoiding highways (so it's planned that way here too).
    func route(_ ride: RideEvent) -> (places: [String], avoidHighways: Bool) {
        // The organiser's own maps link is the route itself.
        if let link = Route.link(in: ride.notes) {
            let linked = Route.linkPlaces(link)
            if linked.count >= 2 { return (linked, Route.linkAvoidsHighways(link)) }
        }
        let written = Route.places(meetingPlace: ride.location, notes: ride.notes)
        if written.count >= 2 { return (written, false) }
        let found = state.foundRoutes[ride.id].flatMap { $0.from == Route.fingerprint(ride) ? $0 : nil }
        if let found, found.places.count >= 2 { return (found.places, found.avoidHighways ?? false) }
        guard let venue = found?.places.first ?? written.first else { return ([], false) }
        return ([homePlace, venue], false)
    }

    /// Your suburb, as a place to plan from (never your street).
    var homePlace: String { state.settings.homeCity.flatMap { $0.isEmpty ? nil : $0 } ?? state.settings.homeName }
}

extension Route {
    /// What a found route was worked out from, so it's worked out again when the ride's details change, or when
    /// RollCall gets better at it (raise `finderVersion`).
    static func fingerprint(_ ride: RideEvent) -> String {
        stableHash("\(finderVersion)\n" + ride.title + "\n" + ride.location + "\n" + ride.notes)
    }
    /// 2: Google links' dragged-through points on stops given only in the path, and "Avoid highways".
    static let finderVersion = 2
}
