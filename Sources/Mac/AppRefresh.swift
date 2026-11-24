import AppKit
import SwiftUI
import MapKit

extension AppDelegate {
    // MARK: - Refreshing

    /// Reads every source and then looks for more details about your rides, or with `dueOnly` just reads the sources
    /// whose interval has passed.
    func refresh(dueOnly: Bool = false) async {
        guard !refreshing, !Store.picturesOnly else { return }
        let feeds = dueOnly
            ? store.state.feeds.filter { !checking.contains($0.id) && $0.due(lastChecked: store.state.lastChecked[$0.id], lastTried: lastTried[$0.id]) }
            : store.state.feeds
        if dueOnly && feeds.isEmpty { return }
        refreshing = true
        refreshProgress.value = 0
        NotificationCenter.default.post(name: Store.changed, object: nil)
        defer {
            refreshing = false
            refreshProgress.value = nil
            updateBadge()
            NotificationCenter.default.post(name: Store.changed, object: nil)
        }
        let started = Date()
        var refreshed: Set<String> = []
        var changed: [String] = []
        // Problems from sources that have since been removed shouldn't linger.
        store.state.feedErrors = store.state.feedErrors.filter { id, _ in store.state.feeds.contains { $0.id == id } }
        let chatProblem = feeds.contains { $0.type == .chat } ? await Beeper.connectionProblem() : nil
        for (i, feed) in feeds.enumerated() {
            // The sources are most of the work; the last bit is for places, the calendar and routes.
            refreshProgress.value = 0.9 * Double(i) / Double(feeds.count)
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
        refreshProgress.value = 0.9
        scanDownloads(save: false)
        store.prune(refreshedSources: refreshed, refreshStarted: started)
        store.state.lastRefresh = Date()
        store.save()
        await geocoder.fill(store)
        for id in changed where store.decision(id) == .attending { syncCalendar(id) }
        store.save()
        syncDevices()
        announceNewRides()
        await findRoutes()
        if !dueOnly { refreshProgress.value = 0.95; await findMoreDetails() }
        // Booked roadworks take a minute to download: fetched now, so a ride's road alerts are ready when opened.
        if store.state.settings.roadAlertsShown == .currentAndPlanned { Task { _ = try? await RoadAlerts.fetchBooked() } }
    }

    // MARK: - Routes

    /// Works out the route of every upcoming ride that hasn't had one worked out from its current details.
    func findRoutes() async {
        for ride in store.upcoming() { await findRoute(for: ride) }
    }

    /// The start, stops and destination of a ride, checked with Apple Maps, saved so its map can be drawn.
    /// Rides whose details already give the route (a maps link or labelled lines) don't need it.
    func findRoute(for ride: RideEvent) async {
        guard !findingRoutes.contains(ride.id) else { return }
        findingRoutes.insert(ride.id)
        defer { findingRoutes.remove(ride.id) }
        if await store.findRoute(for: ride) { store.save() }
    }

    /// Reads one source and keeps what it found. Returns the ids of rides that changed.
    func readFeed(_ feed: Feed) async -> [String] {
        lastTried[feed.id] = Date()
        guard let (r, changed, replied) = await store.read(feed) else { return [] }
        for id in replied where calendar.authorised { syncCalendar(id) }
        addRecentPosts(r.undated, feed: feed)
        await keepReviews(r.reviews, feed: feed)
        return changed
    }
}
