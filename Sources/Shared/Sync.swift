import Foundation

/// Keeps RollCall on the Mac, iPhone and iPad in step through a folder they can all reach: RollCall in iCloud Drive.
/// Each device writes only its own file there and reads the others', so they never overwrite each other's work.
/// Every choice, change and source carries when it last changed, and the later change wins.
///
/// Rides read from group chats go without the message they came from: chats stay on the Mac.
enum Sync {
    /// A value and when it last changed on the device that wrote it. No value means it was taken away then.
    struct Stamped<T: Codable & Equatable>: Codable, Equatable {
        var value: T?
        var at: Date
    }

    /// What one device shares.
    struct File: Codable {
        var decisions: [String: Stamped<Decision>] = [:]
        var edits: [String: Stamped<RideEdit>] = [:]
        var feeds: [String: Stamped<Feed>] = [:]
        var rides: [String: RideEvent] = [:]
        /// Ride id -> its start, for rides removed on that device.
        var removed: [String: Date] = [:]
        /// Nothing until you've set some on that device (or in a file from an older RollCall).
        var settings: [String: Stamped<SharedSetting>]? = nil
        /// How many chats that device reads (only the Mac does), so the others can say they're connected.
        var chats: Int? = nil
    }

    /// Why sharing didn't work, or didn't work fully, in words to show.
    struct Problem: LocalizedError, Equatable {
        var errorDescription: String?
    }

    /// A setting that has to match: every device writes the same calendar events, and shares the same past rides.
    enum SharedSetting: Codable, Equatable {
        case together(Together), crew([String: CrewLinks]), keepDays(Int)
    }

    /// The Mac's own file is Mac.json.
    static let macName = "Mac"

    #if os(macOS)
    /// The Mac's folder for it, in iCloud Drive (nil when iCloud Drive is off).
    static var macFolder: URL? {
        let drive = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        guard FileManager.default.fileExists(atPath: drive.path) else { return nil }
        return drive.appendingPathComponent("RollCall", isDirectory: true)
    }
    #endif

    /// Stamps what's here now: unchanged values keep their old time, changed or removed ones get `time`.
    /// Removals are remembered for two weeks, long enough for the other devices to see them.
    static func stamp<T>(_ current: [String: T], previous: [String: Stamped<T>], at time: Date) -> [String: Stamped<T>] {
        var out: [String: Stamped<T>] = [:]
        let forgetBefore = time.addingTimeInterval(-Double(Store.maxKeepDays) * 86400)
        for key in Set(current.keys).union(previous.keys) {
            if let p = previous[key], p.value == current[key] {
                if p.value != nil || p.at > forgetBefore { out[key] = p }
            } else {
                out[key] = Stamped(value: current[key], at: time)
            }
        }
        return out
    }

    /// Takes the other device's later changes into `mine`, and returns them (nil for ones it took away).
    static func later<T>(_ other: [String: Stamped<T>], than mine: inout [String: Stamped<T>]) -> [(key: String, value: T?)] {
        var changes: [(key: String, value: T?)] = []
        for (key, o) in other where o.at > (mine[key]?.at ?? .distantPast) && o.value != mine[key]?.value {
            mine[key] = o
            changes.append((key, o.value))
        }
        return changes
    }

    /// Rides as this device shares them: a chat ride without its message.
    static func shared(_ events: [String: RideEvent]) -> [String: RideEvent] {
        events.mapValues { e in
            var e = e
            if isFromChat(e) { e.notes = "" }
            return e
        }
    }

    /// Your changes to rides as this device shares them: a chat ride's without its notes, which hold its message.
    static func shared(_ edits: [String: RideEdit], _ events: [String: RideEvent]) -> [String: RideEdit] {
        edits.reduce(into: [:]) { out, change in
            var edit = change.value
            if isFromChat(events[change.key]) { edit.notes = "" }
            out[change.key] = edit
        }
    }

    static func isFromChat(_ ride: RideEvent?) -> Bool { ride?.source.hasPrefix("beeper-") == true }

    // MARK: - Files

    /// Reads the file and every other device's, takes in their changes, and writes this device's file again if it
    /// changed. Returns the rides to update in the calendar. `name` is this device's file.
    ///
    /// Nothing is shared when this device's own file is there but can't be read (it's only in iCloud and this device is
    /// offline, say): without it, everything here would look newly changed. Another device's unreadable file is left
    /// for next time, and the rest are taken in; `problem` says so.
    ///
    /// A device that's `joining` takes on what the others have: its own choices and sources count as older than theirs,
    /// and a file it left from before it was set up again is ignored (otherwise everything missing since would look
    /// removed, and be removed on the others too). It can't join without the Mac's file: the rides would all seem new
    /// when they came later.
    @MainActor
    static func run(_ store: Store, folder: URL, name: String, joining: Bool = false, now: Date = Date()) throws -> (changed: [String], problem: String?) {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let mineURL = folder.appendingPathComponent(name + ".json")
        let names = try fileNames(in: folder)
        let oldData = read(mineURL)
        if oldData == nil, !joining, names.contains(mineURL.lastPathComponent) {
            throw Problem(errorDescription: "RollCall can't read its own file in iCloud Drive just now, so nothing was shared. It'll keep trying.")
        }
        let previous = joining ? nil : oldData.flatMap { try? Store.decoder.decode(File.self, from: $0) }
        // A file of its own that makes no sense is as good as none: what the others have counts, as when joining.
        let startingAgain = joining || (oldData != nil && previous == nil)

        var others: [File] = []
        var problem: String?
        for other in names where other != mineURL.lastPathComponent {
            let device = "your \(other.dropLast(".json".count))"
            let joiningIt = joining && other == macName + ".json"
            let data = read(folder.appendingPathComponent(other))
            if let file = data.flatMap({ try? Store.decoder.decode(File.self, from: $0) }) {
                others.append(file)
                continue
            }
            problem = data != nil ? "RollCall doesn't understand what \(device) shared. Update RollCall on both devices."
                : "RollCall can't read what \(device) shared just now" + (joiningIt ? ". Give iCloud a minute and choose the folder again."
                                                                          : ", so its latest changes aren't here yet. It'll keep trying.")
            if joiningIt { throw Problem(errorDescription: problem) }
        }
        let (file, changed) = store.exchange(previous: previous, others: others, now: startingAgain ? Date(timeIntervalSince1970: 0) : now)
        let data = try Store.encoder.encode(file)
        if data != oldData { try write(data, to: mineURL) }
        return (changed, problem)
    }

    /// Takes this device's file away, when it stops sharing for good. Left there, setting up again would look like
    /// removing everything the file has.
    static func forget(folder: URL, name: String) {
        let file = folder.appendingPathComponent(name + ".json")
        NSFileCoordinator().coordinate(writingItemAt: file, options: .forDeleting, error: nil) { try? FileManager.default.removeItem(at: $0) }
    }

    /// Every device's file. One iCloud hasn't downloaded yet shows as ".Name.json.icloud".
    static func fileNames(in folder: URL) throws -> [String] {
        let real = try FileManager.default.contentsOfDirectory(atPath: folder.path).map { n in
            n.hasPrefix(".") && n.hasSuffix(".icloud") ? String(n.dropFirst().dropLast(".icloud".count)) : n
        }
        return Set(real).filter { $0.hasSuffix(".json") }.sorted()
    }

    /// The folder is the one RollCall on the Mac shares through.
    static func isMacs(_ folder: URL) -> Bool {
        (try? fileNames(in: folder))?.contains(macName + ".json") == true
    }

    /// Reads through iCloud, which downloads the file first when it isn't on this device yet.
    static func read(_ url: URL) -> Data? {
        var data: Data?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: nil) { data = try? Data(contentsOf: $0) }
        return data
    }

    static func write(_ data: Data, to url: URL) throws {
        var failure: Error?
        var refused: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &refused) { u in
            do { try data.write(to: u, options: .atomic) } catch { failure = error }
        }
        if let problem = failure ?? refused { throw problem }
    }
}

extension Sync.File {
    /// Reads a file from an older or newer RollCall. Anything this version doesn't know (a new setting or kind of source,
    /// say) is left out rather than losing the whole file. Left out isn't taken away: that's an entry without a value.
    init(from decoder: Decoder) throws {
        struct Known<T: Decodable>: Decodable {
            var value: T?
            init(from decoder: Decoder) throws { value = try? decoder.singleValueContainer().decode(T.self) }
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func get<T: Decodable>(_ key: CodingKeys) throws -> [String: T] {
            try c.decode([String: Known<T>].self, forKey: key).compactMapValues(\.value)
        }
        decisions = try get(.decisions)
        edits = try get(.edits)
        feeds = try get(.feeds)
        rides = try get(.rides)
        removed = try get(.removed)
        settings = c.contains(.settings) ? try get(.settings) : nil
        chats = try c.decodeIfPresent(Int.self, forKey: .chats)
    }
}

extension Store {
    private var sharedSettings: [String: Sync.SharedSetting] {
        var out: [String: Sync.SharedSetting] = [:]
        out["together"] = state.settings.together.map { .together($0) }
        out["keepDays"] = state.settings.keepDismissedDays.map { .keepDays($0) }
        if !state.crew.isEmpty { out["crew"] = .crew(state.crew) }
        return out
    }

    /// Takes in the other devices' files and returns this device's, plus the rides whose decision changed.
    @MainActor
    func exchange(previous: Sync.File?, others: [Sync.File], now: Date = Date()) -> (file: Sync.File, changed: [String]) {
        let sharedFeeds = { Dictionary(self.state.feeds.filter { $0.type != .chat }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }
        var mine = Sync.File(decisions: Sync.stamp(state.decisions, previous: previous?.decisions ?? [:], at: now),
                             edits: Sync.stamp(Sync.shared(state.rideEdits, state.events), previous: previous?.edits ?? [:], at: now),
                             feeds: Sync.stamp(sharedFeeds(), previous: previous?.feeds ?? [:], at: now))
        var settings = Sync.stamp(sharedSettings, previous: previous?.settings ?? [:], at: now)
        var changed: Set<String> = []
        for other in others {
            for (id, start) in other.removed where state.removedRides[id] == nil {
                state.removedRides[id] = start
                state.events[id] = nil
                changed.insert(id)
            }
            for (id, d) in Sync.later(other.decisions, than: &mine.decisions) {
                state.decisions[id] = d
                changed.insert(id)
            }
            for (id, theirs) in Sync.later(other.edits, than: &mine.edits) {
                var edit = theirs
                // A chat ride's change comes without its notes: keep this device's own.
                if Sync.isFromChat(state.events[id] ?? other.rides[id]) { edit?.notes = state.events[id]?.notes ?? "" }
                state.rideEdits[id] = edit
                guard let edit, var e = state.events[id]?.applying(edit) else { continue }
                // The new place's spot, when the other device has found it.
                if e.latitude == nil, let there = other.rides[id], there.location == e.location {
                    e.latitude = there.latitude; e.longitude = there.longitude
                }
                e.distanceKm = distance(e)
                state.events[id] = e
                changed.insert(id)
            }
            for (id, feed) in Sync.later(other.feeds, than: &mine.feeds) {
                if let feed {
                    if let i = state.feeds.firstIndex(where: { $0.id == id }) { state.feeds[i] = feed } else { state.feeds.append(feed) }
                } else {
                    forgetFeed(id)
                }
            }
            for (key, new) in Sync.later(other.settings ?? [:], than: &settings) {
                switch new {
                case .together(let t): state.settings.together = t
                case .crew(let c): state.crew = c
                case .keepDays(let days): state.settings.keepDismissedDays = days
                // The last group's links were taken away.
                case nil: if key == "crew" { state.crew = [:] }
                }
                // Riding together is on the calendar events of the rides you're going to.
                changed.formUnion(state.calendarItems.keys)
            }
            // Ones over for longer than you keep them don't come back.
            for (id, ride) in other.rides where state.removedRides[id] == nil && ride.finish >= keptSince(now) {
                if let have = state.events[id], have.lastSeen >= ride.lastSeen { continue }
                var r = ride
                // Keep this device's own copy of a chat ride's message (only the Mac has one).
                if r.notes.isEmpty, let have = state.events[id] { r.notes = have.notes }
                // A device without Apple Intelligence can't read the week's meeting place; your changes may not have got there yet.
                r = MeetingPlaces.settled(r, old: state.events[id])
                if let edit = state.rideEdits[id] { r = r.applying(edit) }
                if r.latitude == nil, let have = state.events[id], have.location == r.location {
                    r.latitude = have.latitude; r.longitude = have.longitude
                }
                r.distanceKm = distance(r)
                state.events[id] = r
            }
        }
        mine.settings = settings
        mine.rides = Sync.shared(state.events)
        mine.removed = state.removedRides
        let chats = state.feeds.filter { $0.type == .chat }.count
        mine.chats = chats > 0 ? chats : nil
        state.macChats = others.compactMap(\.chats).max()
        return (mine, changed.sorted())
    }
}
