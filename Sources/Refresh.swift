import Foundation

/// What one source produced on a refresh.
struct SourceResult {
    var events: [ICSEvent] = []
    /// Events whose date and place were read from post text.
    var guessed: [ICSEvent] = []
    /// Ride-related posts with no date found, to show under "Posts to look at".
    var undated: [PostItem] = []
    /// Chat conversations that mention times or days, for the user to review.
    var reviews: [PlanReview] = []
}

/// Reads each kind of source. Pages are fetched one at a time with small pauses,
/// and each forum thread is only read once.
@MainActor
enum SourceReader {
    static let threadsPerRefresh = 6
    static let detailPagesPerRefresh = 8
    /// Posts and threads older than this are skipped: their rides have likely happened.
    static let recentDays = Double(Store.maxKeepDays)

    static func read(_ feed: Feed, store: Store, now: Date = Date()) async throws -> SourceResult {
        switch feed.type {
        case .calendar:
            // Your Facebook events include birthdays and gigs too, so that calendar keeps only the bike ones.
            return SourceResult(events: ICSParser.parse(try await Fetcher.download(feed.url))
                .filter { wanted(feed, "\($0.title) \($0.notes) \($0.location)") })
        case .webpage:
            return try await readWebpage(feed, store: store)
        case .posts:
            return try await readPosts(feed, store: store, now: now)
        case .forum:
            return try await readForum(feed, store: store, now: now)
        case .chat:
            return try await readChat(feed, store: store, now: now)
        }
    }

    /// Forums and the user's own riding chats are already about motorbikes, so any ride word will do there.
    /// General websites and blogs have to mention motorbikes clearly.
    nonisolated static func wanted(_ feed: Feed, _ text: String) -> Bool {
        guard feed.keywordFilter ?? false else { return true }
        return RideWords.matches(text, strict: feed.type == .webpage || feed.type == .posts)
    }

    // MARK: Web pages with schema.org events

    static func readWebpage(_ feed: Feed, store: Store) async throws -> SourceResult {
        let page = try await Web.get(feed.url)
        var events = Web.jsonLDEvents(page.text, base: page.finalURL)
            .filter { wanted(feed, "\($0.title) \($0.notes) \($0.location)") }
        // Listings often give only the date; the event's own page has the time and place.
        var fetched = 0
        for (i, e) in events.enumerated() where e.allDay || e.location.isEmpty {
            let id = Store.eventID(source: feed.id, item: e)
            if let old = store.state.events[id] {
                // Its own page was read before: keep what it added, so the listing's fewer details don't replace it.
                if store.state.rideEdits[id] == nil { events[i] = keepingDetails(e, from: old) }
                continue
            }
            guard fetched < detailPagesPerRefresh, let url = e.url, url != feed.url else { continue }
            fetched += 1
            guard let detail = try? await Web.get(url),
                  let full = Web.jsonLDEvents(detail.text, base: detail.finalURL).first else { continue }
            var merged = full
            merged.uid = e.uid
            events[i] = merged
            try? await Task.sleep(nanoseconds: 800_000_000)
        }
        return SourceResult(events: events)
    }

    /// A listing's event with the time (while it's still on the same day), place and notes an earlier read of its
    /// own page found. A listing that gives a new day, a time or a place is newer, so it wins.
    nonisolated static func keepingDetails(_ e: ICSEvent, from old: RideEvent) -> ICSEvent {
        var e = e
        if e.allDay, !old.allDay, Calendar.current.isDate(old.start, inSameDayAs: e.start) {
            e.start = old.start; e.end = old.end; e.allDay = false
        }
        if e.location.isEmpty { e.location = old.location }
        if e.notes.count < old.notes.count { e.notes = old.notes }
        return e
    }

    // MARK: RSS / Atom

    static func readPosts(_ feed: Feed, store: Store, now: Date) async throws -> SourceResult {
        let page = try await Web.get(feed.url)
        var result = SourceResult()
        for post in Web.parseFeed(page.text) {
            let key = "\(feed.id):\(post.id)"
            guard store.state.seenPosts[key] == nil else { continue }
            if let p = post.published, now.timeIntervalSince(p) > recentDays * 86400 { continue }
            store.state.seenPosts[key] = now
            classify(post, text: "\(post.title)\n\(post.text)", feed: feed, into: &result, now: now)
        }
        return result
    }

    // MARK: XenForo forums (NetRider)

    static func readForum(_ feed: Feed, store: Store, now: Date) async throws -> SourceResult {
        let page = try await Web.get(feed.url)
        var result = SourceResult()

        // Calendar events linked straight from the page (the events list, or "upcoming events" boxes).
        var eventLinks = Web.xenForoEventLinks(page.text, base: page.finalURL)

        var threadsRead = 0
        for t in Web.xenForoThreads(page.text, base: page.finalURL) {
            let key = "\(feed.id):\(t.id)"
            guard store.state.seenPosts[key] == nil else { continue }
            if let s = t.started, now.timeIntervalSince(s) > recentDays * 86400 { continue }
            guard threadsRead < threadsPerRefresh else { break }
            threadsRead += 1
            guard let thread = try? await Web.get(t.url) else { continue }
            store.state.seenPosts[key] = now
            let linked = Web.xenForoEventLinks(thread.text, base: thread.finalURL)
            if let first = linked.first {
                // The thread was made from a forum calendar event: use its exact details.
                if !eventLinks.contains(first) { eventLinks.append(first) }
            } else {
                let body = Web.firstPostText(thread.text)
                let post = PostItem(id: t.id, title: t.title, link: t.url, published: t.started, text: body)
                classify(post, text: "\(t.title)\n\(body)", feed: feed, into: &result, now: now)
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }

        for link in eventLinks.prefix(15) {
            let exportURL = link.hasSuffix("/") ? link + "export" : link + "/export"
            guard let text = try? await Fetcher.download(exportURL) else { continue }
            for var e in ICSParser.parse(text) {
                if e.url == nil { e.url = link }
                if wanted(feed, "\(e.title) \(e.notes) \(e.location)") { result.events.append(e) }
            }
            try? await Task.sleep(nanoseconds: 600_000_000)
        }
        return result
    }

    // MARK: Beeper chats (WhatsApp and others)

    /// Two weeks of messages are read the first time: older chat is no longer relevant, and its rides have likely
    /// happened. Each message only raises a review the first time it's seen.
    nonisolated static let chatLookBackDays = Double(Store.maxKeepDays)

    /// Where reading a chat starts: after the first time, just the messages since the last check, and a quiet gap's
    /// worth before them so a new message still has the start of its conversation.
    nonisolated static func chatReadFrom(lastChecked: Date?, now: Date) -> Date {
        max(now.addingTimeInterval(-chatLookBackDays * 86400), (lastChecked ?? .distantPast).addingTimeInterval(-PlanFinder.gap))
    }

    static func readChat(_ feed: Feed, store: Store, now: Date) async throws -> SourceResult {
        let chatID = Beeper.chatID(of: feed)
        let since = chatReadFrom(lastChecked: store.state.lastChecked[feed.id], now: now)
        var result = SourceResult()
        var lines: [ChatLine] = []
        var posts: [String: PostItem] = [:]
        var newIDs = Set<String>()
        // Every message read is kept for context; only new ones can raise a review.
        for m in try await Beeper.messages(chatID: chatID, since: since) {
            guard let post = chatPost(m, chatID: chatID) else { continue }
            lines.append(PlanFinder.line(from: post, sender: chatSender(m)))
            posts[m.id] = post
            let key = "\(feed.id):\(m.id)"
            if store.state.seenPosts[key] == nil {
                store.state.seenPosts[key] = now
                newIDs.insert(m.id)
            }
        }
        var found = PlanFinder.find(lines, newIDs: newIDs, feedID: feed.id, chatID: chatID, now: now)
        // Plans already under review, or added as rides, take in the replies that settle their details.
        let following = store.state.reviews.values.filter { $0.feedID == feed.id && ($0.status == .open || $0.status == .added) }
            .sorted { $0.updated > $1.updated }
        let grown = PlanFinder.followUps(lines, newIDs: newIDs, found: &found, existing: following, now: now)
        result.reviews = grown + found
        // "Anyone keen for a ride soon?" with no day goes to Posts to look at.
        let inReview = Set(result.reviews.flatMap { $0.lines.map(\.id) })
        for id in newIDs where !inReview.contains(id) {
            guard let post = posts[id] else { continue }
            if RidePlan.judge(post.text, sent: post.published ?? now, now: now).kind == .maybe { result.undated.append(post) }
        }
        result.undated.sort { ($0.published ?? now) < ($1.published ?? now) }
        return result
    }

    /// The sender's name, or nil when a network only gives an internal id like "@discordgo_123:beeper.local".
    nonisolated static func chatSender(_ m: Beeper.Message) -> String? {
        guard let who = m.senderName, !who.isEmpty, !who.hasPrefix("@") else { return nil }
        return who
    }

    /// Turns a chat message into a post, or nil for reactions, deleted messages and one-word replies.
    nonisolated static func chatPost(_ m: Beeper.Message, chatID: String) -> PostItem? {
        if m.isDeleted == true || m.isHidden == true || m.type == "REACTION" { return nil }
        // Beeper sends rich text: turn <br> and &amp; back into plain text.
        var text = Web.plainText(m.text ?? "")
        if let t = m.fullTitle, !t.isEmpty, !text.contains(t) { text += "\n" + t }
        let urls = (m.links ?? []).compactMap(\.url)
        for u in urls where !text.contains(u) { text += "\n" + u }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 12 else { return nil }
        // A shared Facebook event beats the chat message: it's where the RSVP button is.
        let mentioned = urls + Web.allMatches(#"(https?://[^\s<>"]+)"#, in: text)
        let link = mentioned.first { $0.contains("facebook.com/events/") || $0.contains("fb.me/e/") }
            ?? Beeper.chatLink(chatID: chatID, messageID: m.id)
        var title = TextDetect.title(from: text)
        if let who = chatSender(m) { title = "\(who): \(title)" }
        return PostItem(id: m.id, title: title, link: link, published: m.date, text: text)
    }

    // MARK: Turning a post into a ride (or not)

    nonisolated static func classify(_ post: PostItem, text: String, feed: Feed, into result: inout SourceResult, now: Date) {
        guard wanted(feed, text) else { return }
        let found = TextDetect.scan(text, now: now)
        guard let start = found.start else {
            result.undated.append(post)
            return
        }
        let snippet = post.text.count > 600 ? String(post.text.prefix(600)) + "…" : post.text
        result.guessed.append(ICSEvent(
            uid: "post:\(feed.id):\(post.id)",
            title: post.title.isEmpty ? TextDetect.title(from: post.text) : post.title,
            start: start,
            end: found.hasTime ? start.addingTimeInterval(3 * 3600) : nil,
            allDay: !found.hasTime,
            location: found.address ?? "",
            notes: snippet,
            url: post.link))
    }
}
