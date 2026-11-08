import AppKit
import SwiftUI
import MapKit

extension AppDelegate {
    // MARK: - Refreshing

    /// Reads every source, or with `dueOnly` just those whose interval has passed.
    func refresh(dueOnly: Bool = false) async {
        guard !refreshing else { return }
        let feeds = dueOnly
            ? store.state.feeds.filter { !checking.contains($0.id) && $0.due(lastChecked: store.state.lastChecked[$0.id], lastTried: lastTried[$0.id]) }
            : store.state.feeds
        if dueOnly && feeds.isEmpty { return }
        refreshing = true
        NotificationCenter.default.post(name: Store.changed, object: nil)
        defer { refreshing = false; updateBadge(); NotificationCenter.default.post(name: Store.changed, object: nil) }
        let started = Date()
        var refreshed: Set<String> = []
        var changed: [String] = []
        // Problems from sources that have since been removed shouldn't linger.
        store.state.feedErrors = store.state.feedErrors.filter { id, _ in store.state.feeds.contains { $0.id == id } }
        let chatProblem = feeds.contains { $0.type == .chat } ? await Beeper.connectionProblem() : nil
        for feed in feeds {
            if feed.type == .chat {
                if let chatProblem {
                    // Check the connection once, rather than waiting for every chat to fail on its own.
                    store.state.feedErrors[feed.id] = chatProblem.localizedDescription
                    lastTried[feed.id] = Date()
                    continue
                }
                // Connected again: the old connection problem goes now, not once this chat has been read.
                if Beeper.connectionMessages.contains(store.state.feedErrors[feed.id] ?? "") { store.state.feedErrors[feed.id] = nil }
            }
            changed += await readFeed(feed)
            // Only calendar feeds list every event each time, so only they can show a ride was dropped.
            if feed.type == .calendar, store.state.feedErrors[feed.id] == nil { refreshed.insert(feed.id) }
            updateBadge()
        }
        scanDownloads(save: false)
        store.prune(refreshedSources: refreshed, refreshStarted: started)
        store.state.lastRefresh = Date()
        store.save()
        await geocoder.fill(store)
        for id in changed where store.decision(id) == .attending { syncCalendar(id) }
        store.save()
        await findRoutes()
    }

    // MARK: - Routes

    /// Works out the route of every upcoming ride that hasn't had one worked out from its current details.
    func findRoutes() async {
        for ride in store.upcoming() { await findRoute(for: ride) }
    }

    /// The start, stops and destination of a ride, checked with Apple Maps, saved so its map can be drawn.
    /// Rides whose details already give the route (a maps link or labelled lines) don't need it.
    func findRoute(for ride: RideEvent) async {
        let from = Route.fingerprint(ride)
        // Nothing to work out when the details already give the route: a full maps link, or labelled places.
        let given = Route.link(in: ride.notes).map(Route.linkPlaces) ?? Route.places(meetingPlace: ride.location, notes: ride.notes)
        guard given.count < 2, store.state.foundRoutes[ride.id]?.from != from, !findingRoutes.contains(ride.id) else { return }
        findingRoutes.insert(ride.id)
        defer { findingRoutes.remove(ride.id) }
        let s = store.state.settings
        store.state.foundRoutes[ride.id] = await RouteFinder.find(ride, home: CLLocationCoordinate2D(latitude: s.homeLatitude, longitude: s.homeLongitude))
        store.save()
    }

    /// Reads one source and keeps what it found. Returns the ids of rides that changed.
    func readFeed(_ feed: Feed) async -> [String] {
        lastTried[feed.id] = Date()
        do {
            let r = try await SourceReader.read(feed, store: store)
            var changed = store.merge(r.events, source: feed.id, sourceName: feed.name)
            changed += store.merge(r.guessed, source: feed.id, sourceName: feed.name, needsCheck: true)
            if feed.id == FeedLinks.facebookCalendarID {
                // Only your own Facebook calendar's replies are yours; other calendars' are someone else's.
                for id in store.carryResponses(r.events, source: feed.id) where calendar.authorised { syncCalendar(id) }
            }
            addRecentPosts(r.undated, feed: feed)
            await keepReviews(r.reviews, feed: feed)
            store.state.feedErrors[feed.id] = nil
            store.state.lastChecked[feed.id] = Date()
            return changed
        } catch {
            store.state.feedErrors[feed.id] = error.localizedDescription
            return []
        }
    }
}
