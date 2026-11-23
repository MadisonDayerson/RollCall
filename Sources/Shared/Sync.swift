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
    }

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
            if e.source.hasPrefix("beeper-") { e.notes = "" }
            return e
        }
    }

    // MARK: - Files

    /// Reads the file and every other device's, takes in their changes, and writes this device's file again if it
    /// changed. Returns the rides whose Going/Maybe/Skip changed, for the calendar. `name` is this device's file.
    @MainActor
    static func run(_ store: Store, folder: URL, name: String, now: Date = Date()) throws -> [String] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let mineURL = folder.appendingPathComponent(name + ".json")
        let oldData = read(mineURL)
        let previous = oldData.flatMap { try? Store.decoder.decode(File.self, from: $0) }
        let others = otherFiles(in: folder, besides: mineURL.lastPathComponent).compactMap { read($0) }
            .compactMap { try? Store.decoder.decode(File.self, from: $0) }
        let (file, changed) = store.exchange(previous: previous, others: others, now: now)
        let data = try Store.encoder.encode(file)
        if data != oldData { try write(data, to: mineURL) }
        return changed
    }

    /// The other devices' files. A file iCloud hasn't downloaded yet shows as ".Name.json.icloud".
    static func otherFiles(in folder: URL, besides mine: String) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let real = names.map { n in
            n.hasPrefix(".") && n.hasSuffix(".icloud") ? String(n.dropFirst().dropLast(".icloud".count)) : n
        }
        return Set(real).filter { $0.hasSuffix(".json") && $0 != mine }.sorted().map { folder.appendingPathComponent($0) }
    }

    /// Reads through iCloud, which downloads the file first when it isn't on this device yet.
    static func read(_ url: URL) -> Data? {
        var data: Data?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: nil) { data = try? Data(contentsOf: $0) }
        return data
    }

    static func write(_ data: Data, to url: URL) throws {
        var failure: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: nil) { u in
            do { try data.write(to: u, options: .atomic) } catch { failure = error }
        }
        if let failure { throw failure }
    }
}

extension Store {
    /// Takes in the other devices' files and returns this device's, plus the rides whose decision changed.
    @MainActor
    func exchange(previous: Sync.File?, others: [Sync.File], now: Date = Date()) -> (file: Sync.File, changed: [String]) {
        let sharedFeeds = { Dictionary(self.state.feeds.filter { $0.type != .chat }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }
        var mine = Sync.File(decisions: Sync.stamp(state.decisions, previous: previous?.decisions ?? [:], at: now),
                             edits: Sync.stamp(state.rideEdits, previous: previous?.edits ?? [:], at: now),
                             feeds: Sync.stamp(sharedFeeds(), previous: previous?.feeds ?? [:], at: now))
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
            for (id, edit) in Sync.later(other.edits, than: &mine.edits) {
                state.rideEdits[id] = edit
                if let edit, let e = state.events[id] { state.events[id] = e.applying(edit) }
            }
            for (id, feed) in Sync.later(other.feeds, than: &mine.feeds) {
                if let feed {
                    if let i = state.feeds.firstIndex(where: { $0.id == id }) { state.feeds[i] = feed } else { state.feeds.append(feed) }
                } else {
                    forgetFeed(id)
                }
            }
            for (id, ride) in other.rides where state.removedRides[id] == nil {
                if let have = state.events[id], have.lastSeen >= ride.lastSeen { continue }
                var r = ride
                // Keep this device's own copy of a chat ride's message (only the Mac has one).
                if r.notes.isEmpty, let have = state.events[id] { r.notes = have.notes }
                r.distanceKm = distance(r)
                state.events[id] = r
            }
        }
        mine.rides = Sync.shared(state.events)
        mine.removed = state.removedRides
        return (mine, changed.sorted())
    }
}
