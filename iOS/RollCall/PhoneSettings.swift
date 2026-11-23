import SwiftUI

extension PhoneModel {
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

    /// Saves the road alerts key, unless it's empty.
    func saveRoadAlertsKey(_ key: String) -> Bool {
        guard RoadAlerts.saveKey(key) else { return false }
        roadAlertsKeySaved = true
        return true
    }

    func removeRoadAlertsKey() {
        RoadAlerts.removeKey()
        roadAlertsKeySaved = false
    }

    /// Notes whether calendars may be used, which can change in the Settings app.
    func checkCalendar() {
        calendar.checkAccess()
        calendarAllowed = calendar.authorised
    }

    /// Asks to use calendars, then adds the rides you're already going to (from the Mac, say).
    func allowCalendar() async {
        _ = await calendar.requestAccess()
        checkCalendar()
        guard calendarAllowed else { return }
        for ride in store.upcoming() where store.decision(ride.id) == .attending { syncCalendar(ride.id) }
        saved()
    }

    /// Closes setup and reads the sources.
    func finishSetup() async {
        store.state.setupDone = true
        settingUp = false
        saved()
        await refresh()
    }

    /// Removes the rides, sources, settings and road alerts key kept on this device, and starts setup again. The RollCall calendar
    /// stays in Calendar.
    func deleteAllData() {
        stopSharing()
        removeRoadAlertsKey()
        try? FileManager.default.removeItem(at: store.file)
        store.state = AppState()
        state = store.state
    }
}
