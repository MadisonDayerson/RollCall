import Foundation

enum Decision: String, Codable {
    case undecided, attending, maybe, skip
}

enum FeedKind: String, Codable {
    case calendar   // .ics / webcal / Meetup
    case webpage    // a page with schema.org events in it (Eventbrite, club sites)
    case posts      // RSS / Atom: blogs, forums that offer feeds
    case forum      // XenForo forum section or events list (NetRider)
    case chat       // a Beeper chat (WhatsApp, Messenger, Signal… bridged through Beeper)
}

/// A place rides come from: a Meetup group, a club calendar, a website or a forum.
struct Feed: Codable, Equatable {
    var id: String
    var name: String
    var url: String
    /// Page to open so the user can join the group themselves.
    var groupURL: String?
    var kind: FeedKind? = nil
    /// Only keep items that mention motorcycles or rides (for general listings).
    var keywordFilter: Bool? = nil
    /// Minutes between automatic checks: nil uses the default for this kind of source, 0 means only when asked.
    var every: Int? = nil
    /// The chat app behind a Beeper chat (WhatsApp, Messenger…).
    var network: String? = nil

    var type: FeedKind { kind ?? .calendar }
    var interval: Int { every ?? Feed.defaultInterval(type) }

    /// Chats move fast and are cheap to read; websites and forums change slowly, so they're checked less.
    static func defaultInterval(_ kind: FeedKind) -> Int {
        switch kind {
        case .chat: return 15
        case .calendar: return 180
        case .webpage, .posts, .forum: return 360
        }
    }
    static let intervals = [5, 15, 30, 60, 180, 360, 720, 1440, 0]

    static func describe(_ minutes: Int) -> String {
        switch minutes {
        case 0: return "Only when I check"
        case ..<60: return "Every \(minutes) minutes"
        case 60: return "Every hour"
        case 1440: return "Once a day"
        default: return "Every \(minutes / 60) hours"
        }
    }

    /// Time for an automatic check: never read, or the interval has passed since the last try.
    func due(lastChecked: Date?, lastTried: Date?, now: Date = Date()) -> Bool {
        guard interval > 0 else { return false }
        guard let last = [lastChecked, lastTried].compactMap({ $0 }).max() else { return true }
        // A little slack so a once-a-minute timer doesn't miss a slot by a few seconds.
        return now.timeIntervalSince(last) >= Double(interval * 60) - 30
    }

    /// The app or site this source belongs to, for grouping: WhatsApp, Meetup, NetRider…
    var app: String {
        if type == .chat {
            if let n = network, !n.isEmpty { return n }
            if let r = name.range(of: #"\((.+) via Beeper\)$"#, options: .regularExpression) {
                return String(name[r].dropFirst().dropLast(" via Beeper)".count))
            }
            return "Beeper chats"
        }
        let host = (URL(string: url)?.host ?? "").lowercased()
        let known = ["meetup.com": "Meetup", "netrider.net.au": "NetRider", "eventbrite.": "Eventbrite",
                     "facebook.com": "Facebook", "calendar.google.com": "Google Calendar", "humanitix.com": "Humanitix"]
        if let k = known.first(where: { host.contains($0.key) }) { return k.value }
        switch type {
        case .calendar: return "Calendars"
        case .webpage: return "Websites"
        case .posts: return "News and blogs"
        case .forum: return "Forums"
        case .chat: return "Beeper chats"
        }
    }
}

struct InstagramAccount: Codable, Equatable {
    var handle: String
    var lastOpened: Date?
}

/// Sources suggested during setup. Bump `version` when adding more so existing installs get them.
enum Starter {
    static let version = 2
    static let feeds: [Feed] = [
        Feed(id: "meetup-motorcycle-riders-vic",
             name: "Motorcycle Riders VIC (Meetup)",
             url: "https://www.meetup.com/motorcycle-riders-vic/events/ical/",
             groupURL: "https://www.meetup.com/motorcycle-riders-vic/"),
        Feed(id: "netrider-vic-forum",
             name: "NetRider forum – VIC",
             url: "https://netrider.net.au/forum/vic.69/",
             groupURL: "https://netrider.net.au/forum/vic.69/", kind: .forum, keywordFilter: true),
        Feed(id: "netrider-announcements",
             name: "NetRider forum – Ride & Event Announcements",
             url: "https://netrider.net.au/forum/ride-and-event-announcements.94/",
             groupURL: "https://netrider.net.au/forum/ride-and-event-announcements.94/", kind: .forum, keywordFilter: true),
        Feed(id: "netrider-events",
             name: "NetRider events calendar",
             url: "https://netrider.net.au/events/",
             groupURL: "https://netrider.net.au/events/", kind: .forum, keywordFilter: false),
        Feed(id: "eventbrite-melbourne-motorcycle",
             name: "Eventbrite – motorcycle events in Melbourne",
             url: "https://www.eventbrite.com.au/d/australia--melbourne/motorcycle/",
             groupURL: nil, kind: .webpage, keywordFilter: true),
    ]
    static let instagram = [InstagramAccount(handle: "hooligoon.co")]

    /// What setup suggests for someone's home area: the Victorian groups near Melbourne,
    /// or an Eventbrite search for their own city anywhere else.
    static func suggestions(for s: Settings) -> (feeds: [Feed], instagram: [InstagramAccount]) {
        let region = (s.homeRegion ?? "").lowercased()
        if region == "vic" || region == "victoria" { return (feeds, instagram) }
        guard let city = s.homeCity, !city.isEmpty else { return ([], []) }
        func slug(_ x: String) -> String {
            x.lowercased().folding(options: .diacriticInsensitive, locale: nil)
                .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        }
        let place = [s.homeCountry.map(slug), slug(city)].compactMap { $0 }.joined(separator: "--")
        return ([Feed(id: "eventbrite-\(slug(city))-motorcycle",
                      name: "Eventbrite – motorcycle events in \(city)",
                      url: "https://www.eventbrite.com/d/\(place)/motorcycle/",
                      groupURL: nil, kind: .webpage, keywordFilter: true)], [])
    }
}

struct RideEvent: Codable {
    var id: String
    var title: String
    var start: Date
    var end: Date?
    var allDay: Bool
    var location: String
    var notes: String
    var url: String?
    var source: String          // feed id, "facebook", "file" or "manual"
    var sourceName: String
    var latitude: Double?
    var longitude: Double?
    var distanceKm: Double?
    var lastSeen: Date
    /// Date and place were read from a post's text, so they may be wrong.
    var needsCheck: Bool? = nil

    var isFacebook: Bool { url?.contains("facebook.com") ?? false }
}

struct Settings: Codable {
    var homeName = "Melbourne"
    var homeLatitude = -37.8136
    var homeLongitude = 144.9631
    var radiusKm = 100.0
    var daysAhead = 60
    var watchDownloads = true
    // Filled in by setup when the home area is found (optional so older saves still read).
    var homeCity: String? = nil
    var homeRegion: String? = nil
    var homeCountry: String? = nil
    /// The calendar account (EventKit source) that holds the RollCall calendar: iCloud, Google, Exchange…
    var calendarSourceID: String? = nil
    /// Location sharing, intercom, Discord and tags for riding with friends.
    var together: Together? = nil
    /// Look for new versions on GitHub once a day (nil means yes).
    var checkForUpdates: Bool? = nil
    /// A version the person chose to skip.
    var skippedVersion: String? = nil
    /// Which maps app Route opens (nil means automatic).
    var mapsApp: MapsApp? = nil

    var crew: Together { together ?? Together() }
}

/// Your own changes to a ride's details. They're kept apart from the ride, so a refresh of its source
/// doesn't undo them.
struct RideEdit: Codable, Equatable {
    var title: String
    var start: Date
    var end: Date?
    var allDay: Bool
    var location: String
    var notes: String
    var url: String?
}

extension RideEvent {
    func applying(_ edit: RideEdit) -> RideEvent {
        var e = self
        if edit.location != location { e.latitude = nil; e.longitude = nil; e.distanceKm = nil }  // to be found again
        e.title = edit.title; e.start = edit.start; e.end = edit.end; e.allDay = edit.allDay
        e.location = edit.location; e.notes = edit.notes; e.url = edit.url
        return e
    }
}

struct AppState: Codable {
    var settings = Settings()
    /// New installs start empty; setup suggests sources for the person's area.
    var feeds: [Feed] = []
    var events: [String: RideEvent] = [:]
    var decisions: [String: Decision] = [:]
    /// RideEvent id -> EventKit calendarItemIdentifier for rides added to Apple Calendar.
    var calendarItems: [String: String] = [:]
    /// Location text -> [lat, lon]; an empty array means "couldn't find it".
    var geocodeCache: [String: [Double]] = [:]
    var lastDownloadsScan: Date?
    var lastRefresh: Date?
    var feedErrors: [String: String] = [:]
    /// Feed id -> when it was last read successfully.
    var lastChecked: [String: Date] = [:]
    /// Possible plans from chat conversations, by review id.
    var reviews: [String: PlanReview] = [:]
    var instagram: [InstagramAccount] = []
    /// Post id -> when it was read, so each forum thread is fetched once.
    var seenPosts: [String: Date] = [:]
    /// Recent posts per feed that didn't contain a date, for "Posts to look at".
    var recentPosts: [String: [PostItem]] = [:]
    var postsReadUntil: Date?
    var starterVersion = Starter.version
    /// The setup wizard has been finished (or skipped).
    var setupDone = false
    /// Source id (or "yours") -> that group's own Discord and tags.
    var crew: [String: CrewLinks] = [:]
    /// Ride id -> the details as you changed them.
    var rideEdits: [String: RideEdit] = [:]
    /// Ride id -> its start, for rides you removed, so checking the source again doesn't bring them back.
    var removedRides: [String: Date] = [:]

    init() {}

    // Every field is optional in the file, so older saves keep working when fields are added.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func get<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        settings = get(.settings, Settings())
        feeds = get(.feeds, Starter.feeds)
        events = get(.events, [:])
        decisions = get(.decisions, [:])
        calendarItems = get(.calendarItems, [:])
        geocodeCache = get(.geocodeCache, [:])
        lastDownloadsScan = get(.lastDownloadsScan, nil)
        lastRefresh = get(.lastRefresh, nil)
        feedErrors = get(.feedErrors, [:])
        lastChecked = get(.lastChecked, [:])
        reviews = get(.reviews, [:])
        seenPosts = get(.seenPosts, [:])
        recentPosts = get(.recentPosts, [:])
        postsReadUntil = get(.postsReadUntil, nil)
        setupDone = get(.setupDone, false)
        crew = get(.crew, [:])
        rideEdits = get(.rideEdits, [:])
        removedRides = get(.removedRides, [:])
        let savedVersion: Int = get(.starterVersion, 1)
        instagram = get(.instagram, savedVersion < 2 ? [] : Starter.instagram)
        starterVersion = savedVersion
        if savedVersion < Starter.version {
            // Add starter sources that are new since this file was saved.
            for f in Starter.feeds where !feeds.contains(where: { $0.id == f.id }) { feeds.append(f) }
            for a in Starter.instagram where !instagram.contains(where: { $0.handle == a.handle }) { instagram.append(a) }
            starterVersion = Starter.version
        }
    }
}

final class Store {
    static let folder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("RollCall", isDirectory: true)
        // The app used to be called MotoRides: bring its saved rides and sources across.
        let old = base.appendingPathComponent("MotoRides", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path), FileManager.default.fileExists(atPath: old.path) {
            try? FileManager.default.moveItem(at: old, to: dir)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Rides, chat excerpts and private calendar links: only this Mac user can read them.
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        for name in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dir.appendingPathComponent(name).path)
        }
        return dir
    }()
    let file: URL
    var state: AppState

    init(file: URL = Store.folder.appendingPathComponent("state.json")) {
        self.file = file
        if let data = try? Data(contentsOf: file),
           let s = try? Store.decoder.decode(AppState.self, from: data) {
            state = s
        } else {
            state = AppState()
        }
    }

    func save() {
        guard let data = try? Store.encoder.encode(state) else { return }
        try? data.write(to: file, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        NotificationCenter.default.post(name: Store.changed, object: nil)
    }

    /// Rides are shown within tens of kilometres, so home only needs to be known to about 1 km.
    static func rough(_ degrees: Double) -> Double { (degrees * 100).rounded() / 100 }

    /// Older versions kept whatever was typed as the home area, sometimes a street address, and the exact spot.
    func minimiseHome() {
        var s = state.settings
        if let city = s.homeCity, !city.isEmpty { s.homeName = city }
        s.homeLatitude = Store.rough(s.homeLatitude)
        s.homeLongitude = Store.rough(s.homeLongitude)
        guard s.homeName != state.settings.homeName || s.homeLatitude != state.settings.homeLatitude
                || s.homeLongitude != state.settings.homeLongitude else { return }
        state.settings = s
        save()
    }

    /// Posted after every save, so the window can redraw.
    static let changed = Notification.Name("RollCallStoreChanged")

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func decision(_ id: String) -> Decision { state.decisions[id] ?? .undecided }

    /// Upcoming rides within the radius (or with an unknown location), soonest first.
    /// A ride posted in several places shows once, unless `oneEach` is off (for counting a source's own rides).
    func upcoming(now: Date = Date(), oneEach: Bool = true) -> [RideEvent] {
        let limit = Calendar.current.date(byAdding: .day, value: state.settings.daysAhead, to: now) ?? now
        let rides = state.events.values
            .filter { ($0.end ?? $0.start.addingTimeInterval(3 * 3600)) >= now && $0.start <= limit }
            .filter { e in
                // Rides the user typed in or imported themselves are always shown.
                if Store.userAdded.contains(e.source) { return true }
                // Chats the user picked: their rides count wherever they go.
                if e.source.hasPrefix("beeper-") { return true }
                // Facebook events you said Going or Interested to: you chose them, however far away.
                if e.source == FeedLinks.facebookCalendarID { return true }
                guard let d = e.distanceKm else { return true }
                return d <= state.settings.radiusKm
            }
        return (oneEach ? self.oneEach(rides) : rides).sorted { $0.start < $1.start }
    }

    /// Rides you went on that have finished, most recent first. Distance doesn't matter: you went.
    func past(now: Date = Date()) -> [RideEvent] {
        oneEach(state.events.values.filter { ($0.end ?? $0.start.addingTimeInterval(3 * 3600)) < now && decision($0.id) == .attending })
            .sorted { $0.start > $1.start }
    }

    /// One ride for each set of cross-posts: the one you've decided on, else the fullest event page.
    func oneEach<C: Collection>(_ rides: C) -> [RideEvent] where C.Element == RideEvent {
        CrossPost.groups(Array(rides), same: CrossPost.sameRide).map { group in
            // Ties go by id, so the list doesn't swap rides between refreshes.
            group.sorted { $0.id > $1.id }.max { rank($0).lexicographicallyPrecedes(rank($1)) }!
        }
    }

    /// The same ride posted elsewhere, for "From" on the ride's page.
    func copies(of ride: RideEvent) -> [RideEvent] {
        state.events.values.filter { CrossPost.sameRide(ride, $0) }.sorted { $0.sourceName < $1.sourceName }
    }

    private func rank(_ e: RideEvent) -> [Int] {
        let decided: [Decision: Int] = [.attending: 3, .maybe: 2, .skip: 1, .undecided: 0]
        // An event page (with its RSVP and details) beats a ride typed in or read from a chat or post.
        let page = Store.userAdded.contains(e.source) || e.source.hasPrefix("beeper-") || e.needsCheck == true ? 0 : 1
        return [decided[decision(e.id)] ?? 0, page, e.location.isEmpty ? 0 : 1, e.notes.count]
    }

    /// Adds or refreshes events from one source. Returns ids that changed (for calendar updates).
    @discardableResult
    func merge(_ items: [ICSEvent], source: String, sourceName: String,
               needsCheck: Bool = false, now: Date = Date()) -> [String] {
        var changed: [String] = []
        for item in items {
            let id = Store.eventID(source: source, item: item)
            if state.removedRides[id] != nil { continue }
            var e = RideEvent(
                id: id, title: item.title, start: item.start, end: item.end, allDay: item.allDay,
                location: item.location, notes: item.notes, url: item.url,
                source: source, sourceName: sourceName,
                latitude: item.latitude, longitude: item.longitude, distanceKm: nil, lastSeen: now,
                needsCheck: needsCheck ? true : nil)
            // Your changes win over what the source says.
            if let edit = state.rideEdits[id] { e = e.applying(edit) }
            if let old = state.events[id] {
                // Keep things we worked out earlier.
                if e.latitude == nil, old.location == e.location {
                    e.latitude = old.latitude; e.longitude = old.longitude
                }
                if old.title != e.title || old.start != e.start || old.end != e.end || old.location != e.location {
                    changed.append(id)
                }
            }
            e.distanceKm = distance(e)
            state.events[id] = e
        }
        return changed
    }

    static let userAdded: Set<String> = ["manual", "file", "facebook", "instagram"]

    /// Facebook events get the same id however they arrive, so a re-import updates instead of duplicating.
    static func eventID(source: String, item: ICSEvent) -> String {
        // Forum calendar events can turn up through several forum sections.
        if let u = item.url, u.range(of: #"/events/[a-z0-9-]+\.\d+/?$"#, options: .regularExpression) != nil {
            return "xf:\(u)"
        }
        if let fb = facebookEventID(item.url ?? "") ?? facebookEventID(item.uid) { return "facebook:\(fb)" }
        return "\(source):\(item.uid)"
    }

    static func facebookEventID(_ s: String) -> String? {
        // https://www.facebook.com/events/1234567890/  or UID e1234567890@facebook.com
        for pattern in [#"facebook\.com/events/(?:[^/]+/)*?(\d{6,})"#, #"^e(\d{6,})@facebook\.com"#, #"[?&]eid=(\d{6,})"#] {
            if let r = s.range(of: pattern, options: .regularExpression) {
                let match = String(s[r])
                if let digits = match.range(of: #"\d{6,}"#, options: .regularExpression) {
                    return String(match[digits])
                }
            }
        }
        return nil
    }

    /// Facebook's Share → Copy link gives a short link without the event number
    /// (facebook.com/share/1513oBi2LqL/ or fb.me/e/…). It opens the event in a browser, so it's kept as it is.
    /// Share links for posts, reels, videos and groups (/share/p/, /r/, /v/, /g/) aren't events.
    static func facebookShareLink(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^(?:https?://)?(?:(?:www|m|web)\.)?(?:facebook\.com/share/(?:e/)?[A-Za-z0-9_-]+|fb\.me/e/[A-Za-z0-9_-]+)/?(?:[?#].*)?$"#
        guard t.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
        return t.lowercased().hasPrefix("http") ? t : "https://" + t
    }

    func distance(_ e: RideEvent) -> Double? {
        guard let lat = e.latitude, let lon = e.longitude else { return nil }
        return Store.haversineKm(lat, lon, state.settings.homeLatitude, state.settings.homeLongitude)
    }

    static func haversineKm(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = 6371.0
        let dLat = (lat2 - lat1) * .pi / 180, dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1, sqrt(a)))
    }

    /// Drops past events nobody is attending, plus feed events that vanished from their feed
    /// (cancelled or removed), keeping anything the user marked Attending.
    func prune(refreshedSources: Set<String>, refreshStarted: Date, now: Date = Date()) {
        let weekAgo = now.addingTimeInterval(-7 * 86400)
        for (id, e) in state.events {
            // Rides you went on stay, under Past rides.
            let past = (e.end ?? e.start) < weekAgo && decision(id) != .attending
            let vanished = refreshedSources.contains(e.source) && e.lastSeen < refreshStarted && e.start > now
            if past || (vanished && decision(id) != .attending) {
                state.events[id] = nil
                if past { state.decisions[id] = nil; state.calendarItems[id] = nil }
            }
        }
        state.rideEdits = state.rideEdits.filter { state.events[$0.key] != nil }
        state.removedRides = state.removedRides.filter { $0.value > weekAgo }
        let cutoff = now.addingTimeInterval(-120 * 86400)
        state.seenPosts = state.seenPosts.filter { $0.value > cutoff }
        // Reviews go once the conversation is two weeks old or the plan is well past.
        state.reviews = state.reviews.filter { _, r in
            r.updated > now.addingTimeInterval(-14 * 86400) && (r.summary.start.map { $0 > now.addingTimeInterval(-86400) } ?? true)
        }
        // A dismissed conversation only needs its summary; people's messages aren't kept.
        for (id, r) in state.reviews where r.status == .dismissed && !r.lines.isEmpty { state.reviews[id]?.lines = [] }
    }
}

extension Array where Element: Hashable {
    /// The items in order, without repeats.
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
