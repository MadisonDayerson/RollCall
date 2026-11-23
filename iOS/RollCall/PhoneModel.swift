import SwiftUI

/// What the iPhone and iPad app shows and changes. The rides and sources live in the shared `Store`; `state` is a copy
/// of them that SwiftUI watches, taken after every change.
@MainActor @Observable
final class PhoneModel {
    let store = Store()
    let calendar = CalendarSync()
    let geocoder = Geocoder()
    private(set) var state: AppState
    private(set) var refreshing = false
    /// A problem to show, such as the calendar not being allowed.
    var problem: String?

    init() {
        state = store.state
        calendar.checkAccess()
    }

    /// Saves, and shares the change with RollCall on the Mac (taking in its changes too) when that's set up.
    private func saved() {
        share()
        store.save()
        state = store.state
    }

    // MARK: - Sharing with the Mac

    /// The RollCall folder in iCloud Drive that RollCall on the Mac shares, once chosen in Settings.
    private(set) var macFolder: URL? = PhoneModel.savedFolder()
    private(set) var lastShared: Date?
    var shareProblem: String?

    private static let folderKey = "macFolder"
    private static func savedFolder() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: folderKey) else { return nil }
        var stale = false
        return try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale)
    }

    func shareWithMac(in folder: URL) {
        let allowed = folder.startAccessingSecurityScopedResource()
        defer { if allowed { folder.stopAccessingSecurityScopedResource() } }
        guard let bookmark = try? folder.bookmarkData() else {
            shareProblem = "Couldn't keep access to that folder. Choose it again."
            return
        }
        UserDefaults.standard.set(bookmark, forKey: Self.folderKey)
        macFolder = folder
        saved()
    }

    func stopSharing() {
        UserDefaults.standard.removeObject(forKey: Self.folderKey)
        macFolder = nil
        lastShared = nil
        shareProblem = nil
    }

    /// Takes in what the Mac changed since (called every minute while RollCall is open).
    func shareNow() {
        guard macFolder != nil else { return }
        saved()
    }

    private func share() {
        guard let folder = macFolder else { return }
        let allowed = folder.startAccessingSecurityScopedResource()
        defer { if allowed { folder.stopAccessingSecurityScopedResource() } }
        do {
            let changed = try Sync.run(store, folder: folder, name: UIDevice.current.model)
            if calendar.authorised { for id in changed { syncCalendar(id) } }
            lastShared = Date()
            shareProblem = nil
        } catch {
            shareProblem = error.localizedDescription
        }
    }

    // MARK: - Rides

    struct Section: Identifiable {
        var id: String { name }
        var name: String
        var rides: [RideEvent]
    }

    var sections: [Section] {
        _ = state  // redraw when the rides change
        let all = store.upcoming()
        return [
            Section(name: "Undecided", rides: all.filter { [.undecided, .maybe].contains(store.decision($0.id)) }),
            Section(name: "Going", rides: all.filter { store.decision($0.id) == .attending }),
            Section(name: "Skipped", rides: all.filter { store.decision($0.id) == .skip }),
            Section(name: "Past", rides: store.past()),
        ]
    }

    func decision(_ id: String) -> Decision { state.decisions[id] ?? .undecided }

    func decide(_ id: String, _ d: Decision) async {
        store.state.decisions[id] = d
        state = store.state  // shows the choice while Calendar access is asked for
        if d == .attending, !calendar.authorised { _ = await calendar.requestAccess() }
        syncCalendar(id)
        saved()
    }

    func remove(_ id: String) {
        store.removeRide(id) { syncCalendar($0) }
        saved()
    }

    private func syncCalendar(_ id: String) {
        do {
            try store.syncCalendar(id, using: calendar)
        } catch SyncError.noAccess {
            problem = "RollCall isn't allowed to add rides to your calendar. Turn on Full Access in Settings → Apps → RollCall → Calendars, then mark the ride Going again."
        } catch {
            problem = "Couldn't add the ride to your calendar. \(error.localizedDescription)"
        }
    }

    func directions(for ride: RideEvent, in app: MapsApp? = nil) async -> URL? {
        // Apple Maps comes with every iPhone and iPad.
        await store.directions(for: ride, in: app, hasAppleMaps: true).flatMap(URL.init(string:))
    }

    // MARK: - Refreshing

    /// Reads every source (chats are read on the Mac), then finds where rides are and updates the calendar.
    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        let started = Date()
        var refreshed: Set<String> = []
        var changed: [String] = []
        store.state.feedErrors = store.state.feedErrors.filter { id, _ in store.state.feeds.contains { $0.id == id } }
        for feed in store.state.feeds where feed.type != .chat {
            do {
                let r = try await SourceReader.read(feed, store: store)
                changed += store.merge(r.events, source: feed.id, sourceName: feed.name)
                changed += store.merge(r.guessed, source: feed.id, sourceName: feed.name, needsCheck: true)
                if feed.id == FeedLinks.facebookCalendarID {
                    // Only your own Facebook calendar's replies are yours; other calendars' are someone else's.
                    for id in store.carryResponses(r.events, source: feed.id) where calendar.authorised { syncCalendar(id) }
                }
                store.state.feedErrors[feed.id] = nil
                store.state.lastChecked[feed.id] = Date()
                if feed.type == .calendar { refreshed.insert(feed.id) }
            } catch {
                store.state.feedErrors[feed.id] = error.localizedDescription
            }
            state = store.state
        }
        store.prune(refreshedSources: refreshed, refreshStarted: started)
        store.state.lastRefresh = Date()
        saved()
        await geocoder.fill(store)
        if calendar.authorised {
            for id in changed where store.decision(id) == .attending { syncCalendar(id) }
        }
        saved()
    }

    // MARK: - Sources

    /// Adds a source from a link. Returns a problem to show, or nil when it was added.
    func addSource(_ link: String) async -> String? {
        do {
            let feed = try await Web.discover(link)
            if let existing = store.state.feeds.first(where: { $0.id == feed.id || $0.url == feed.url }) {
                return "\(existing.name) is already one of your sources."
            }
            store.state.feeds.append(feed)
            saved()
            await refresh()
            return nil
        } catch FeedError.privateFeed where link.contains("meetup.com") {
            return "This Meetup group's calendar is private. Join the group, then on its Events tab choose Subscribe / Add to calendar, and paste the link it gives you."
        } catch {
            return error.localizedDescription
        }
    }

    func removeSource(_ id: String) {
        store.forgetFeed(id)
        saved()
    }

    // MARK: - Settings

    /// Finds your suburb. Returns a problem to show, or nil when it was set.
    func setHome(_ place: String) async -> String? {
        let place = place.trimmingCharacters(in: .whitespaces)
        guard !place.isEmpty else { return "Type your suburb or town." }
        guard let found = try? await CLGeocoderShim.find(place) else {
            return "Couldn't find “\(place)”. Try a suburb or town with its state, like Ringwood VIC or Newtown NSW."
        }
        store.setHome(found, typed: place)
        saved()
        return nil
    }

    func change(_ edit: (inout Settings) -> Void) {
        edit(&store.state.settings)
        saved()
    }

    /// Finishes setup with the suggested sources for your area, then reads them.
    func finishSetup(with feeds: [Feed]) async {
        for f in feeds where !store.state.feeds.contains(where: { $0.id == f.id }) { store.state.feeds.append(f) }
        store.state.setupDone = true
        saved()
        await refresh()
    }

    /// Removes the rides, sources and settings kept on this device, and starts setup again. The RollCall calendar
    /// stays in Calendar.
    func deleteAllData() {
        stopSharing()
        try? FileManager.default.removeItem(at: store.file)
        store.state = AppState()
        state = store.state
    }
}
