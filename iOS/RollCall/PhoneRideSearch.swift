import SwiftUI

extension PhoneModel {
    /// Part of pulling down to refresh (not the checks when RollCall opens): looks for more about the rides you're going
    /// to or might go to. Each one with something new shows it under More details on its page.
    func findMoreDetails() async {
        guard AppleModel.available else { return }
        // Finds you haven't dealt with yet stay as they are.
        for ride in store.ridesWantingDetails() where lookups[ride.id] == nil {
            let id = ride.id
            withAnimation(.easeOut(duration: 0.2)) { lookups[id] = .starting }
            let (found, checked) = await store.moreDetails(for: ride) { self.lookups[id] = .looking($0) }
            withAnimation(.easeOut(duration: 0.25)) { lookups[id] = found.isEmpty ? nil : .done(found, checked: checked) }
        }
    }

    /// Adds a found detail to the ride as your own change, and takes it off the list.
    func useFinding(_ f: RideSearch.Finding, rideID id: String) {
        guard let ride = state.events[id] else { return }
        for copy in store.saveEdit(RideSearch.edit(ride, adding: f), to: ride) where calendar.authorised { syncCalendar(copy) }
        lookups[id] = lookups[id]?.without(f)
        saved()
        // A new meeting place is found, for its distance.
        if f.field == .place { Task { await geocoder.fill(store); saved() } }
    }
}
