import Foundation
import CoreLocation

/// Crashes, closures, hazards and roadworks on a ride's route, from the Victorian Department of Transport and
/// Planning's open data (CC BY 4.0): the alerts, and reading them from the feeds. They're matched to a route in
/// `RoadAlertMatching.swift` and downloaded in `RoadAlertDownloads.swift`.
enum RoadAlerts {
    struct Alert: Codable {
        var id: String
        /// Booked works (roadworks, events) rather than something happening now.
        var planned: Bool
        var kind: String
        var impact: String
        var road: String
        var place: String
        var details: String
        var start: Date?
        var end: Date?
        /// When booked works are on, if only at set times (say, weeknights 8 pm for 9 hours).
        var times: [Times] = []
        var spots: [CLLocationCoordinate2D]
        /// Where it's on the route, once matched: for marking on the map.
        var mark: CLLocationCoordinate2D? = nil

        /// "Closures · Planned roadworks · Hume Freeway, Wallan".
        var summary: String {
            [impact == "N/A" ? "" : impact, kind, [road, place].filter { !$0.isEmpty }.joined(separator: ", ")]
                .filter { !$0.isEmpty }.joined(separator: " · ")
        }

        /// Worth a second look on a bike, so shown in orange.
        var closesRoad: Bool {
            impact.localizedCaseInsensitiveContains("road closed") || impact.localizedCaseInsensitiveContains("closures")
        }
    }

    /// The alerts on one road, shown as one: works often come as a record per stretch, ramp and stage.
    struct Road {
        var name: String
        var places: [String]
        var alerts: [Alert]

        /// The most disruptive alert's.
        var impact: String { worst.impact == "N/A" ? "" : worst.impact }
        var kind: String { worst.kind }
        var closesRoad: Bool { worst.closesRoad }
        /// Every alert on it is booked works rather than something happening now.
        var planned: Bool { alerts.allSatisfy(\.planned) }
        var details: String { Array(Set(alerts.map(\.details).filter { !$0.isEmpty })).sorted().joined(separator: "\n") }

        private var worst: Alert {
            alerts.min { RoadAlerts.rank($0) < RoadAlerts.rank($1) }!
        }
    }

    /// One weekly slot of booked works: from a time on a weekday, for a while.
    struct Times: Codable {
        /// 1 is Sunday, as in Calendar.
        var weekday: Int
        var minutes: Int
        var seconds: Double
    }

    enum Failure: Error { case noKey, badKey, failed }

    static let unplannedURL = "https://api.opendata.transport.vic.gov.au/api/opendata/roads/disruptions/unplanned/v3"
    static let plannedURL = "https://api.opendata.transport.vic.gov.au/opendata/roads/disruptions/planned/v1/"
    static let signUpPage = "https://opendata.transport.vic.gov.au/"

    /// How close to the route an alert has to be to be on it.
    static let nearMetres = 50.0
    /// Works that stretch along a road count when this much of them follows the route (or most of a shorter
    /// stretch), so a closure on a road you only cross doesn't.
    static let alongMetres = 200.0
    /// Alerts happening now only matter for rides this soon.
    static let liveHours = 24.0
    /// The feeds give Victorian times without a time zone.
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Australia/Melbourne") ?? .current
        return c
    }()

    // MARK: Reading the feeds

    /// Any GeoJSON coordinates, however deeply nested, as a flat list of spots ([longitude, latitude] pairs).
    private struct Coordinates: Decodable {
        var spots: [CLLocationCoordinate2D] = []
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let pair = try? c.decode([Double].self) {
                if pair.count >= 2 { spots = [CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])] }
            } else if let list = try? c.decode([Coordinates].self) {
                spots = list.flatMap(\.spots)
            }
        }
    }

    private struct Geometry: Decodable {
        var coordinates: Coordinates?
        var geometries: [Geometry]?
        var spots: [CLLocationCoordinate2D] { (coordinates?.spots ?? []) + (geometries ?? []).flatMap(\.spots) }
    }

    private struct Impact: Decodable { var impactType: String? }
    private struct Reference: Decodable { var startIntersectionLocality: String? }

    private struct Unplanned: Decodable {
        struct Meta: Decodable { var total_pages: Int? }
        struct Collection: Decodable { var features: [Feature] }
        struct Feature: Decodable { var geometry: Geometry?; var properties: Properties }
        struct Properties: Decodable {
            var id: String?
            var status: String?
            var eventLocationStatus: String?
            var eventType: String?
            var eventSubType: String?
            var closedRoadName: String?
            var description: String?
            var created: String?
            var impact: Impact?
            var reference: Reference?
        }
        var meta: Meta?
        var data: Collection
    }

    private struct Planned: Decodable {
        struct NextPage: Decodable { var nextPageToken: String?; var hasMoreRecords: Bool? }
        struct Feature: Decodable { var geometry: Geometry?; var properties: Properties }
        struct Properties: Decodable {
            struct Duration: Decodable { var start: String?; var end: String?; var recurrences: [Recurrence]? }
            struct Recurrence: Decodable {
                var startDay: String?
                var daysDuration: Int?
                var startTime: String?
                var duration: String?
                var allDay: Bool?
            }
            var id: String?
            var status: String?
            var eventType: String?
            var eventSubtype: String?
            var closedRoadName: String?
            var startIntersectionLocality: String?
            var description: String?
            var duration: Duration?
            var impact: Impact?
        }
        var features: [Feature]
        var nextPageDetails: NextPage?
    }

    /// Alerts happening now, and how many pages the feed has. Ones marked over are left out.
    static func readUnplanned(_ data: Data) -> (alerts: [Alert], pages: Int)? {
        guard let reply = try? JSONDecoder().decode(Unplanned.self, from: data) else { return nil }
        let alerts = reply.data.features.compactMap { f -> Alert? in
            let p = f.properties
            guard p.status != "Inactive", p.eventLocationStatus != "Inactive", let spots = f.geometry?.spots, !spots.isEmpty
            else { return nil }
            let (road, place) = roadAndPlace(p.closedRoadName, p.reference?.startIntersectionLocality)
            return Alert(id: p.id ?? UUID().uuidString, planned: false, kind: p.eventSubType ?? p.eventType ?? "",
                         impact: p.impact?.impactType ?? "", road: road, place: place, details: p.description ?? "",
                         start: date(p.created), end: nil, spots: spots)
        }
        return (alerts, reply.meta?.total_pages ?? 1)
    }

    /// Booked works that aren't over by `now`, and the token for the next page if there is one.
    static func readPlanned(_ data: Data, now: Date = Date()) -> (alerts: [Alert], next: String?)? {
        guard let reply = try? JSONDecoder().decode(Planned.self, from: data) else { return nil }
        let alerts = reply.features.compactMap { f -> Alert? in
            let p = f.properties
            let end = endDate(p.duration?.end)
            guard p.status != "Inactive", (end ?? .distantFuture) > now, let spots = f.geometry?.spots, !spots.isEmpty
            else { return nil }
            let (road, place) = roadAndPlace(p.closedRoadName, p.startIntersectionLocality)
            return Alert(id: p.id ?? UUID().uuidString, planned: true, kind: p.eventSubtype ?? p.eventType ?? "",
                         impact: p.impact?.impactType ?? "", road: road, place: place, details: p.description ?? "",
                         start: date(p.duration?.start), end: end,
                         times: (p.duration?.recurrences ?? []).compactMap(times), spots: spots)
        }
        let more = reply.nextPageDetails?.hasMoreRecords == true ? reply.nextPageDetails?.nextPageToken : nil
        return (alerts, more?.isEmpty == false ? more : nil)
    }

    /// "WEST GATE FREEWAY " becomes "West Gate Freeway".
    private static func tidy(_ text: String?) -> String {
        (text ?? "").trimmingCharacters(in: .whitespaces).capitalized
    }

    /// The road and suburb, from names given either way: "Clyde Road" in "Berwick", or "Clyde Road - Berwick".
    private static func roadAndPlace(_ road: String?, _ place: String?) -> (road: String, place: String) {
        let r = tidy(road), p = tidy(place)
        let parts = r.components(separatedBy: " - ")
        guard p.isEmpty, parts.count >= 2 else { return (r, p) }
        return (parts[0].trimmingCharacters(in: .whitespaces), parts[1].trimmingCharacters(in: .whitespaces))
    }

    /// A feed time like "2026-11-10T18:30:00", in Victorian time.
    static func date(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ssXXXXX"] {
            f.dateFormat = format
            if let d = f.date(from: text) { return d }
        }
        return nil
    }

    /// An end at midnight means the works run to the end of that day.
    private static func endDate(_ text: String?) -> Date? {
        guard let d = date(text) else { return nil }
        return d == calendar.startOfDay(for: d) ? calendar.date(byAdding: .day, value: 1, to: d) : d
    }

    private static func times(_ r: Planned.Properties.Recurrence) -> Times? {
        let days = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        guard let day = r.startDay?.lowercased(), let i = days.firstIndex(of: day) else { return nil }
        if r.allDay == true { return Times(weekday: i + 1, minutes: 0, seconds: Double(max(1, r.daysDuration ?? 1)) * 86400) }
        guard let minutes = minutes(r.startTime), let length = seconds(r.duration) else { return nil }
        // The length runs to the end time, so works from 9 pm to 5 am come as "PT-16H"; none means all day.
        return Times(weekday: i + 1, minutes: minutes, seconds: length <= 0 ? length + 86400 : length)
    }

    /// A time of day like "9:30 PM" or "21:30", in minutes after midnight.
    static func minutes(_ text: String?) -> Int? {
        guard let text else { return nil }
        let pm = text.uppercased().hasSuffix("PM"), am = text.uppercased().hasSuffix("AM")
        let hm = text.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard hm.count >= 2, hm[0] < 24, hm[1] < 60 else { return nil }
        let hour = pm ? hm[0] % 12 + 12 : am ? hm[0] % 12 : hm[0]
        return hour * 60 + hm[1]
    }

    /// An ISO 8601 length like "PT6H", "P1DT2H30M" or "PT-14H-30M", in seconds.
    static func seconds(_ text: String?) -> Double? {
        guard let text, text.hasPrefix("P") else { return nil }
        var total = 0.0, number = "", inTime = false
        for ch in text.dropFirst() {
            if ch == "T" { inTime = true; continue }
            if ch.isNumber || ch == "." || (ch == "-" && number.isEmpty) { number.append(ch); continue }
            guard let n = Double(number) else { return nil }
            switch (ch, inTime) {
            case ("D", false): total += n * 86400
            case ("H", true): total += n * 3600
            case ("M", true): total += n * 60
            case ("S", true): total += n
            default: return nil
            }
            number = ""
        }
        return number.isEmpty ? total : nil
    }
}
