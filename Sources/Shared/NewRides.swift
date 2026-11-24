import Foundation

/// Which rides are new, for telling you about them once.
extension Store {
    /// Rides to decide on that weren't here the last time this was asked. The first time there's nothing to compare
    /// with, so none are.
    ///
    /// Left out: rides you added yourself, another posting of a ride already here, and the next date of a regular ride
    /// (a weekly ride gets a new date each week). A ride whose place is still to be found waits until RollCall knows how
    /// far away it is.
    func newRides(now: Date = Date()) -> [RideEvent] {
        let known = state.knownRides
        let found = upcoming(now: now).filter { ride in
            guard let known, decision(ride.id) == .undecided, !Store.userAdded.contains(ride.source), placed(ride) else { return false }
            return known[ride.id] == nil && !copies(of: ride).contains { known[$0.id] != nil } && !isRepeat(ride, known: known)
        }
        // What waits for its place, or for its day to come within the days shown, isn't known yet.
        let shown = Calendar.current.date(byAdding: .day, value: state.settings.daysAhead, to: now) ?? now
        state.knownRides = (known ?? [:]).filter { $0.value > now }
        for e in state.events.values where known == nil || (placed(e) && e.start <= shown) { state.knownRides?[e.id] = e.finish }
        return found
    }

    /// Counts the rides here as known: they came with a source you've just added, or from a Mac just joined.
    func noteRides(from source: String? = nil) {
        guard state.knownRides != nil else { return }
        for e in state.events.values where source == nil || e.source == source { state.knownRides?[e.id] = e.finish }
    }

    /// Its place has been looked up, or it doesn't give one.
    private func placed(_ ride: RideEvent) -> Bool {
        ride.latitude != nil || ride.location.isEmpty || state.geocodeCache[ride.location.lowercased()] != nil
    }

    /// Another date of a ride the same source already had. Names read from messages and posts are too loose to go on.
    private func isRepeat(_ ride: RideEvent, known: [String: Date]) -> Bool {
        guard ride.needsCheck != true, !ride.source.hasPrefix("beeper-") else { return false }
        return state.events.values.contains { known[$0.id] != nil && $0.id != ride.id && $0.source == ride.source && $0.title == ride.title }
    }
}
