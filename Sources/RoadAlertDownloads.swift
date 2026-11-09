import Foundation
import CoreLocation

/// Downloads Victoria's road alerts with the rider's own key: alerts happening now kept in memory for 10 minutes,
/// booked works kept on disk (public road data only) and downloaded again after 6 hours.
extension RoadAlerts {
    private static var live: (at: Date, alerts: [Alert])?
    private static var booked: Saved?
    private static var downloadingBooked: Task<[Alert], Error>?

    /// Booked works as downloaded, kept on disk.
    private struct Saved: Codable { var at: Date; var alerts: [Alert] }
    static let bookedFile = Store.folder.appendingPathComponent("roadworks.json")
    /// Booked works older than this are downloaded again.
    static let bookedHours = 6.0
    /// Saved booked works younger than this are shown while new ones download; older ones are waited for.
    static let staleHours = 48.0

    /// Alerts happening now in Victoria: one download, kept in memory for 10 minutes.
    @MainActor
    static func fetchLive(now: Date = Date()) async throws -> [Alert] {
        let key = try savedKey()
        if let kept = live, now.timeIntervalSince(kept.at) < 600 { return kept.alerts }
        var alerts: [Alert] = []
        var page = 1, pages = 1
        repeat {
            guard let reply = readUnplanned(try await get(unplannedURL + "?limit=500&page=\(page)", key: key)) else { throw Failure.failed }
            alerts += reply.alerts
            pages = min(reply.pages, 10)
            page += 1
        } while page <= pages
        live = (now, alerts)
        return alerts
    }

    /// Victoria's booked works that aren't over. Downloading them is about 20 pages, a few seconds apart to keep
    /// within the feed's limit, so it takes a minute or so: they're kept on disk and downloaded again after 6
    /// hours, with the saved ones shown meanwhile. One download at a time.
    @MainActor
    static func fetchBooked(now: Date = Date()) async throws -> [Alert] {
        let key = try savedKey()
        if booked == nil {
            // About a third of a second to read, so it's read away from the window.
            let file = bookedFile
            booked = await Task.detached { try? JSONDecoder().decode(Saved.self, from: Data(contentsOf: file)) }.value
        }
        let age = booked.map { now.timeIntervalSince($0.at) / 3600 } ?? .infinity
        if age < bookedHours, let kept = booked { return kept.alerts }
        let task = downloadingBooked ?? Task { @MainActor () throws -> [Alert] in
            defer { downloadingBooked = nil }
            let alerts = try await downloadBooked(key: key, now: now)
            booked = Saved(at: now, alerts: alerts)
            if let data = try? JSONEncoder().encode(booked) { try? data.write(to: bookedFile, options: .atomic) }
            return alerts
        }
        downloadingBooked = task
        if age < staleHours, let kept = booked { return kept.alerts.filter { ($0.end ?? .distantFuture) > now } }
        return try await task.value
    }

    @MainActor
    private static func downloadBooked(key: String, now: Date) async throws -> [Alert] {
        var alerts: [Alert] = []
        var token: String? = nil
        var asked = ContinuousClock.now
        for page in 0..<40 {
            // The feed allows 20 requests a minute: the next starts 3.2 seconds after the last one did.
            if page > 0 { try await Task.sleep(until: asked + .seconds(3.2)) }
            asked = .now
            guard let reply = readPlanned(try await get(plannedURL + "?format=GeoJson", key: key, next: token), now: now)
            else { throw Failure.failed }
            alerts += reply.alerts
            token = reply.next
            if token == nil { break }
        }
        return alerts
    }

    private static func savedKey() throws -> String {
        guard let key = Keychain.roads.read(), !key.isEmpty else { throw Failure.noKey }
        return key
    }

    @MainActor
    private static func get(_ address: String, key: String, next: String? = nil) async throws -> Data {
        guard let url = URL(string: address) else { throw Failure.failed }
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.setValue(Web.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(key, forHTTPHeaderField: "KeyID")
        if let next { request.setValue(next, forHTTPHeaderField: "NextPageToken") }
        guard let (data, reply) = try? await Net.session.data(for: request) else { throw Failure.failed }
        switch (reply as? HTTPURLResponse)?.statusCode {
        case 200: return data
        case 401, 403: throw Failure.badKey
        default: throw Failure.failed
        }
    }

    /// Forgets the downloaded alerts, after the key changes.
    @MainActor static func forget() {
        live = nil
        booked = nil
        try? FileManager.default.removeItem(at: bookedFile)
    }
}

/// Saved as [latitude, longitude], for keeping booked works on disk.
extension CLLocationCoordinate2D: @retroactive Codable {
    public init(from decoder: Decoder) throws {
        let pair = try decoder.singleValueContainer().decode([Double].self)
        guard pair.count == 2 else { throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a spot")) }
        self.init(latitude: pair[0], longitude: pair[1])
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode([latitude, longitude])
    }
}
