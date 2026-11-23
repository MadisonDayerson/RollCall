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
    /// A problem to show, such as the calendar not being allowed.
    var problem: String?
    /// The RollCall folder in iCloud Drive that RollCall on the Mac shares, once chosen in Settings.
    var macFolder: URL? = PhoneModel.savedFolder()
    var lastShared: Date?
    var shareProblem: String?

    init() {
        state = store.state
        calendar.checkAccess()
    }

    /// Saves, and shares the change with RollCall on the Mac (taking in its changes too) when that's set up.
    func saved() {
        share()
        store.save()
        state = store.state
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

    func findRoute(for ride: RideEvent) async {
        if await store.findRoute(for: ride) { saved() }
    }

    func directions(for ride: RideEvent, in app: MapsApp? = nil) async -> URL? {
        // Apple Maps comes with every iPhone and iPad.
        await store.directions(for: ride, in: app, hasAppleMaps: true).flatMap(URL.init(string:))
    }

}
