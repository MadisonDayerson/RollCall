import Foundation
import CoreLocation

/// Turns whatever the user pastes into a feed we can download.
enum FeedLinks {
    /// Accepts a Meetup group page, a webcal:// link, or any http(s) .ics link.
    static func normalise(_ raw: String) -> Feed? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        if s.lowercased().hasPrefix("webcal://") { s = "https://" + s.dropFirst("webcal://".count) }
        if !s.lowercased().hasPrefix("http") { s = "https://" + s }
        guard let url = URL(string: s), let host = url.host?.lowercased() else { return nil }

        if host.hasSuffix("meetup.com") {
            // https://www.meetup.com/en-AU/some-group/events/123/ -> group "some-group"
            let parts = url.path.split(separator: "/").map(String.init)
                .filter { !$0.isEmpty && !($0.count == 5 && $0.contains("-") && $0.first!.isLowercase && $0.last!.isUppercase) }
            guard let group = parts.first, group != "find", group != "topics" else { return nil }
            // A signed link copied from the group page ("Add to calendar") is kept as is.
            let feedURL = url.path.contains("/ical") ? s : "https://www.meetup.com/\(group)/events/ical/"
            return Feed(id: "meetup-\(group.lowercased())",
                        name: "\(group) (Meetup)",
                        url: feedURL,
                        groupURL: "https://www.meetup.com/\(group)/")
        }
        if host.hasSuffix("facebook.com") { return nil }  // handled as a single event, not a feed
        let name = host.replacingOccurrences(of: "www.", with: "")
        return Feed(id: "ics-\(stableHash(s))-\(name)", name: name, url: s, groupURL: nil)
    }
}

/// Swift's hashValue changes every launch; feed ids must not.
func stableHash(_ s: String) -> String {
    var h: UInt64 = 5381
    for b in s.utf8 { h = (h &* 33) ^ UInt64(b) }
    return String(h % 0xFFFFFF, radix: 16)
}

enum Fetcher {
    static func download(_ urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.setValue("RollCall/1.0 (personal calendar reader)", forHTTPHeaderField: "User-Agent")
        req.setValue("text/calendar, */*", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            if http.statusCode == 403 || http.statusCode == 401 {
                throw FeedError.privateFeed
            }
            throw FeedError.http(http.statusCode)
        }
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        guard text.contains("BEGIN:VCALENDAR") else { throw FeedError.notCalendar }
        return text
    }
}

enum FeedError: LocalizedError {
    case privateFeed, http(Int), notCalendar
    var errorDescription: String? {
        switch self {
        case .privateFeed: return "This group's calendar is private. Copy its personal calendar link from the group page instead."
        case .http(let c): return "The site answered with error \(c)."
        case .notCalendar: return "That link isn't a calendar feed."
        }
    }
}

/// Facebook lets you download an event as an .ics file ("Add to calendar" / "Export event").
/// Those land in ~/Downloads; this picks up new ones that came from Facebook.
enum DownloadsWatcher {
    static func newFacebookFiles(since: Date?) -> [URL] {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: downloads, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
        else { return [] }
        return items.filter { url in
            guard url.pathExtension.lowercased() == "ics" else { return false }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if let since, modified <= since { return false }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
            return text.contains("facebook.com")
        }
    }
}

/// Looks up map coordinates for event locations so rides far from home can be hidden.
/// Results are cached in the state file; Apple's geocoder is used one request at a time.
@MainActor
final class Geocoder {
    private let geocoder = CLGeocoder()

    func fill(_ store: Store) async {
        let s = store.state.settings
        let region = CLCircularRegion(center: CLLocationCoordinate2D(latitude: s.homeLatitude, longitude: s.homeLongitude),
                                      radius: 300_000, identifier: "home")
        for (id, e) in store.state.events where e.latitude == nil && !e.location.isEmpty {
            let key = e.location.lowercased()
            var coords = store.state.geocodeCache[key]
            if coords == nil {
                let found = try? await geocoder.geocodeAddressString(e.location, in: region)
                if let loc = found?.first?.location {
                    coords = [loc.coordinate.latitude, loc.coordinate.longitude]
                } else {
                    coords = []
                }
                store.state.geocodeCache[key] = coords
                try? await Task.sleep(nanoseconds: 1_200_000_000)  // be gentle with Apple's rate limit
            }
            guard let c = coords, c.count == 2, var ev = store.state.events[id] else { continue }
            ev.latitude = c[0]; ev.longitude = c[1]
            ev.distanceKm = store.distance(ev)
            store.state.events[id] = ev
        }
    }
}
