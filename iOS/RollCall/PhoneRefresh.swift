import SwiftUI

extension PhoneModel {
    /// Reads every source (chats are read on the Mac), then finds where rides are and updates the calendar.
    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        let started = Date()
        var refreshed: Set<String> = []
        var changed: [String] = []
        // Problems from sources that have since been removed shouldn't linger.
        store.state.feedErrors = store.state.feedErrors.filter { id, _ in store.state.feeds.contains { $0.id == id } }
        for feed in store.state.feeds where feed.type != .chat {
            if let (_, found, replied) = await store.read(feed) {
                changed += found
                for id in replied where calendar.authorised { syncCalendar(id) }
                // Only calendar feeds list every event each time, so only they can show a ride was dropped.
                if feed.type == .calendar { refreshed.insert(feed.id) }
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
        // Booked roadworks take a minute to download: fetched now, so a ride's road alerts are ready when opened.
        if store.state.settings.roadAlertsShown == .currentAndPlanned { Task { _ = try? await RoadAlerts.fetchBooked() } }
    }

    // MARK: - Sources

    /// Adds a source from a link and reads it. Returns a problem to show, or nil when it was added.
    func addSource(_ link: String) async -> String? {
        let problem = await follow(link)
        if problem == nil { await refresh() }
        return problem
    }

    /// Adds a source from a link. Returns a problem to show, or nil when it was added.
    func follow(_ link: String) async -> String? {
        if FeedLinks.facebookCalendar(link) != nil { return await connectFacebook(link) }
        do {
            let feed = try await Web.discover(link)
            if let existing = store.state.feeds.first(where: { $0.id == feed.id || $0.url == feed.url }) {
                return "\(existing.name) is already one of your sources."
            }
            store.state.feeds.append(feed)
            saved()
            return nil
        } catch FeedError.privateFeed where link.contains("meetup.com") {
            return "This Meetup group's calendar is private. Join the group, then on its Events tab choose Subscribe / Add to calendar, and paste the link it gives you."
        } catch {
            return error.localizedDescription
        }
    }

    func follow(_ feed: Feed, _ on: Bool) {
        if !on {
            store.forgetFeed(feed.id)
        } else if !store.state.feeds.contains(where: { $0.id == feed.id }) {
            store.state.feeds.append(feed)
        }
        saved()
    }

    var facebookConnected: Bool { state.feeds.contains { $0.id == FeedLinks.facebookCalendarID } }

    /// Connects Facebook's calendar of your events. Returns a problem to show, or nil when it's connected.
    func connectFacebook(_ link: String) async -> String? {
        guard let feed = FeedLinks.facebookCalendar(link) else {
            return "That isn't your Facebook events calendar link. It starts with https://www.facebook.com/events/ical/"
        }
        do {
            try await store.followFacebookCalendar(feed)
            saved()
            return nil
        } catch {
            return "Facebook didn't send your events. \(error.localizedDescription) Copy the link from Facebook again and paste it."
        }
    }

    func removeSource(_ id: String) {
        store.forgetFeed(id)
        saved()
    }
}
