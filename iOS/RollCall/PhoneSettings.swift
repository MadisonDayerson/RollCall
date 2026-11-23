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
