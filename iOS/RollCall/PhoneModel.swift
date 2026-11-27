import SwiftUI

/// What the iPhone and iPad app shows and changes. The rides and sources live in the shared `Store`; `state` is a copy
/// of them that SwiftUI watches, taken after every change.
@MainActor @Observable
final class PhoneModel {
    let store = Store()
    let calendar = CalendarSync()
    let geocoder = Geocoder()
    var state: AppState
    var refreshing = false
    /// How far Refresh has got, 0 to 1; nil when it isn't checking.
    let refreshProgress = Box<Double?>(nil)
    /// A problem to show, such as the calendar not being allowed.
    var problem: String?
    var tab: PhoneTab = .home
    /// A ride to open on the Rides tab, from its notification.
    var rideToOpen: String?
    /// A day to show on the Rides tab, from Home.
    var dayToOpen: Date?
    /// Nil until you've been asked.
    var notificationsAllowed: Bool?
    /// The RollCall folder in iCloud Drive that RollCall on the Mac shares, once chosen in Settings.
    var macFolder: URL? = PhoneModel.savedFolder()
    var lastShared: Date?
    var shareProblem: String?
    /// The setup wizard is open again, from Settings.
    var settingUp = false
    var roadAlertsKeySaved = Keychain.roads.read() != nil
    var calendarAllowed = false
    /// Ride id -> more details Refresh is looking for, while it looks and what it found (until RollCall quits).
    var lookups: [String: RideSearch.Lookup] = [:]

    init() {
        state = store.state
        checkCalendar()
    }

    /// Saves, shares the change with RollCall on the Mac (taking in its changes too) when that's set up, and tells you
    /// about new rides.
    func saved() {
        share()
        _ = RideNotice.announce(store)  // saved just below
        store.save()
        state = store.state
    }

    // MARK: - Rides

    /// The list's headings, as on the Mac.
    var sections: [GroupedRides] {
        _ = state  // redraw when the rides change
        return store.groupedRides()
    }

    /// The rides a calendar shows: coming up and not skipped, and those you went on.
    var calendarRides: [RideEvent] {
        _ = state
        return store.calendarRides()
    }

    func decision(_ id: String) -> Decision { state.decisions[id] ?? .undecided }

    func decide(_ id: String, _ d: Decision) async {
        store.state.decisions[id] = d
        state = store.state  // shows the choice while Calendar access is asked for
        if d == .attending, !calendar.authorised {
            _ = await calendar.requestAccess()
            checkCalendar()
        }
        syncCalendar(id)
        saved()
    }

    /// Removes a ride, or takes one that's over off Past (its calendar event stays).
    func remove(_ ride: RideEvent) {
        if ride.finish < Date() { store.forgetPastRide(ride.id) } else { store.removeRide(ride.id) { syncCalendar($0) } }
        saved()
    }

    func syncCalendar(_ id: String) {
        do {
            try store.syncCalendar(id, using: calendar)
        } catch SyncError.noAccess {
            problem = "RollCall isn't allowed to add rides to your calendar. Turn on Full Access in Settings → Apps → RollCall → Calendars, then mark the ride Going again."
        } catch {
            problem = "Couldn't add the ride to your calendar. \(error.localizedDescription)"
        }
    }

    /// The places a ride's route goes through, read from the state SwiftUI watches so the map redraws when they're found.
    func route(_ ride: RideEvent) -> (places: [String], avoidHighways: Bool) {
        _ = state.foundRoutes[ride.id]
        return store.route(ride)
    }

    /// Where the ride is from, read from the state SwiftUI watches so it follows the sources.
    func sourceLine(_ ride: RideEvent) -> String {
        _ = state
        return store.sourceLine(ride)
    }

    func findRoute(for ride: RideEvent) async {
        if await store.findRoute(for: ride) { saved() }
    }

    func directions(for ride: RideEvent, in app: MapsApp? = nil) async -> URL? {
        // Apple Maps comes with every iPhone and iPad.
        await store.directions(for: ride, in: app, hasAppleMaps: true).flatMap(URL.init(string:))
    }
}
