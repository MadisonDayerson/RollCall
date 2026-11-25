import Foundation
import CoreLocation

/// Changes to your rides and sources that the Mac and iPhone apps make the same way. Each app saves afterwards and
/// tells you about problems in its own way.
@MainActor
extension Store {
    /// Your home area, kept as just the suburb and a rough spot (about 1 km), never a street address.
    func setHome(_ found: Places.Found, typed place: String) {
        state.settings.homeName = found.city ?? place
        state.settings.homeLatitude = Store.rough(found.spot.latitude)
        state.settings.homeLongitude = Store.rough(found.spot.longitude)
        state.settings.homeCity = found.city
        state.settings.homeRegion = found.state
        state.settings.homeCountry = found.country
        for (id, var e) in state.events {
            e.distanceKm = distance(e)
            state.events[id] = e
        }
    }

    /// Follows Facebook's calendar of your events (replacing an older link), after checking Facebook sends it.
    @MainActor
    func followFacebookCalendar(_ feed: Feed) async throws {
        _ = try await Fetcher.download(feed.url)
        state.feeds.removeAll { $0.id == feed.id }
        state.feeds.append(feed)
    }

    /// What removing a source does, for the question before it. Sharing takes it off the other devices too.
    func removalNote(_ feed: Feed, shared: Bool) -> String {
        "Its rides will disappear from the list. Rides you marked Going stay in your calendar."
            + (shared && feed.type != .chat ? " It's removed from the devices RollCall shares with too." : "")
    }

    func forgetFeed(_ id: String) {
        state.feeds.removeAll { $0.id == id }
        forgetReadings(id)
    }

    /// Forgets what was read from a source: its rides (except ones you're going to), posts, plans, problems and which
    /// posts it had, so adding it again (or giving it a new link) reads it afresh.
    func forgetReadings(_ id: String) {
        state.feedErrors[id] = nil
        state.recentPosts[id] = nil
        state.lastChecked[id] = nil
        state.reviews = state.reviews.filter { $0.value.feedID != id }
        state.seenPosts = state.seenPosts.filter { !$0.key.hasPrefix(id + ":") }
        for (eid, e) in state.events where e.source == id && decision(eid) != .attending {
            state.events[eid] = nil
        }
    }

    /// Removes the ride and every cross-posted copy of it. Rides from a source stay removed when it's checked again.
    /// `unlist` takes each copy out of the calendar while it's marked Skip.
    func removeRide(_ id: String, unlist: (String) -> Void) {
        guard let ride = state.events[id] else { return }
        for e in [ride] + copies(of: ride) {
            state.decisions[e.id] = .skip
            unlist(e.id)
            state.events[e.id] = nil
            state.decisions[e.id] = nil
            state.rideEdits[e.id] = nil
            state.removedRides[e.id] = e.start
        }
    }

    /// Makes your change to a ride, which stays through refreshes. Every copy of a cross-posted ride gets it, so the
    /// copies still match and show as one ride. A chat ride's notes hold its message, so copies from elsewhere, which sync
    /// shares in full, keep their own. Returns the copies' ids, for the calendar.
    func saveEdit(_ edit: RideEdit, to ride: RideEvent) -> [String] {
        let all = [ride] + copies(of: ride)
        for copy in all {
            var edit = edit
            if Sync.isFromChat(ride), !Sync.isFromChat(copy) { edit.notes = copy.notes }
            state.rideEdits[copy.id] = edit
            var e = copy.applying(edit)
            e.distanceKm = distance(e)
            state.events[copy.id] = e
        }
        return all.map(\.id)
    }

    /// Puts the ride in the RollCall calendar while you're going, and takes it out when you're not.
    func syncCalendar(_ id: String, using calendar: CalendarSync) throws {
        let existing = state.calendarItems[id]
        if decision(id) == .attending, let ride = state.events[id] {
            guard calendar.authorised else { throw SyncError.noAccess }
            let card = Crew.card(ride, together: state.settings.crew, links: state.crew[Crew.key(forSource: ride.source)])
            state.calendarItems[id] = try calendar.upsert(ride, existingID: existing, crewCard: card)
        } else if let existing {
            if !leavesCalendarEvent(id) { calendar.remove(itemID: existing) }
            state.calendarItems[id] = nil
        }
    }

    /// A ride that's over keeps its calendar event, as a record of the day.
    func leavesCalendarEvent(_ id: String) -> Bool { state.events[id].map { $0.finish < Date() } ?? false }

    /// Takes a finished ride off Past rides; its calendar event stays.
    func forgetPastRide(_ id: String) {
        state.decisions[id] = nil
        state.calendarItems[id] = nil
        prune(refreshedSources: [], refreshStarted: Date())
    }

    /// Reads one source and keeps its rides, noting when it was checked or what went wrong. Returns what it gave (nil
    /// after a problem), the rides that changed, and those whose reply on your Facebook calendar was taken in.
    func read(_ feed: Feed) async -> (result: SourceResult, changed: [String], replied: [String])? {
        do {
            let r = try await SourceReader.read(feed, store: self)
            var changed = merge(r.events, source: feed.id, sourceName: feed.name)
            changed += merge(r.guessed, source: feed.id, sourceName: feed.name, needsCheck: true)
            changed += await readMeetingPlaces(from: feed.id)
            // Only your own Facebook calendar's replies are yours; other calendars' are someone else's.
            let replied = feed.id == FeedLinks.facebookCalendarID ? carryResponses(r.events, source: feed.id) : []
            state.feedErrors[feed.id] = nil
            // Everything in a source you've just added is new, so none of it is news.
            if state.lastChecked[feed.id] == nil { noteRides(from: feed.id) }
            state.lastChecked[feed.id] = Date()
            return (r, changed, replied)
        } catch {
            // Stopped part way (a background check that ran out of time): nothing's wrong with the source.
            if Task.isCancelled { return nil }
            state.feedErrors[feed.id] = error.localizedDescription
            return nil
        }
    }

    /// Works out a ride's start, stops and destination with Apple Maps (and the on-device model), unless its details
    /// already give the route or it was worked out from these details before. Returns whether it found a new one.
    func findRoute(for ride: RideEvent) async -> Bool {
        // Nothing to work out when the details already give the route: a full maps link, or labelled places. The
        // organiser's link comes first, so a short one is always followed, even when the post also lists places.
        let given = Route.link(in: ride.notes).map(Route.linkPlaces) ?? Route.places(meetingPlace: ride.location, notes: ride.notes)
        guard given.count < 2, state.foundRoutes[ride.id]?.from != Route.fingerprint(ride) else { return false }
        state.foundRoutes[ride.id] = await RouteFinder.find(ride, home: homeSpot)
        return true
    }

    /// The rough spot of your suburb, for finding places near you.
    var homeSpot: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: state.settings.homeLatitude, longitude: state.settings.homeLongitude)
    }

    /// The link that opens a ride's route: the organiser's shared route, or else directions from your suburb in the
    /// maps app you pick (or the one chosen in Settings). Automatic uses Apple Maps for a simple trip when it's there,
    /// and Google Maps for stops.
    func directions(for ride: RideEvent, in chosen: MapsApp? = nil, hasAppleMaps: Bool) async -> String? {
        if chosen == nil, let link = Route.link(in: ride.notes) {
            return link.replacingOccurrences(of: "http://", with: "https://")
        }
        // The maps apps already start from your suburb, so it isn't repeated as a stop.
        let places = Array(routePlaces(ride).drop { $0 == homePlace })
        guard let first = places.first else { return nil }
        let s = state.settings
        let home = s.homeCity?.nilIfEmpty
        var app = chosen ?? s.mapsApp ?? .automatic
        if app == .automatic { app = places.count == 1 && hasAppleMaps ? .apple : .google }
        if app == .apple, !hasAppleMaps { app = .google }
        switch app {
        case .apple:
            return Route.appleMaps(from: home, to: first)
        case .waze:
            return Route.waze(to: first)
        case .kurviger:
            let spot = homeSpot
            let found = await RoutePlanner.locate(places, near: spot) ?? []
            // A place Apple Maps couldn't find: Google Maps can still search for it by name.
            guard !found.isEmpty else { return Route.googleMaps(from: home, through: places) }
            return Route.kurviger(through: ([spot] + found).map { (latitude: $0.latitude, longitude: $0.longitude) })
        default:
            return Route.googleMaps(from: home, through: places)
        }
    }
}
