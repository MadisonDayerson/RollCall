import AppKit
import SwiftUI

extension AppDelegate {
    // MARK: - Plans to review

    /// Saves conversations that moved on, summarises them, and lets the user know when one becomes a possible plan
    /// (or its time or place changes). Rides added from a plan follow it when the chat changes the time or place.
    func keepReviews(_ found: [PlanReview], feed: Feed) async {
        for var r in found {
            let old = store.state.reviews[r.id]
            if let old {
                r.created = old.created
                r.rideID = old.rideID
                // Added stays added; a dismissed conversation comes back only because it moved on.
                r.status = old.status == .added ? .added : .open
            }
            r.summary = await PlanSummariser.summarise(r, chatName: feed.name)
            // The on-device model read it and found no plan: keep it out of the way.
            if !r.summary.isPlan, r.status == .open { r.status = .dismissed }
            r.dismissed = nil
            if r.status == .dismissed { r.lines = [] }  // keep no more of people's messages than needed
            let changed = old?.summary.start != r.summary.start || old?.summary.place != r.summary.place
            let wasReady = old?.status == .open && old?.summary.isReady == true
            // The same message sent to several chats: one heads-up is enough.
            let echo = store.state.reviews.values.contains { $0.status == .open && $0.id != r.id && CrossPost.samePlan($0, r) }
            store.state.reviews[r.id] = r
            if r.status == .open, r.summary.isReady, !echo, !wasReady || changed { notify(r, chatName: feed.name) }
            if r.status == .added, changed, let old {
                followPlan(r, was: old.summary, said: r.lines.filter { l in !old.lines.contains { $0.id == l.id } }, chatName: feed.name)
            }
        }
    }

    /// A ride added from a chat plan takes the plan's new time or place, keeping its length, but only when one of the
    /// new messages (`said`) gives a time or a place: a summary read again can come out differently on its own. Your
    /// own edits (Edit…) still win, and a ride you're going to updates its calendar event.
    private func followPlan(_ r: PlanReview, was: PlanSummary, said: [ChatLine], chatName: String) {
        guard let id = r.rideID, var ride = store.state.events[id], store.state.rideEdits[id] == nil else { return }
        let s = r.summary
        var notes: [String] = []
        if let start = s.start, s.hasTime, start != was.start, start > Date(), said.contains(where: \.mentionsWhen) {
            let length = ride.end.map { $0.timeIntervalSince(ride.start) } ?? 3 * 3600
            ride.start = start
            ride.end = start.addingTimeInterval(length)
            notes.append(PlanFinder.describe(start, hasTime: true))
        }
        if let place = s.place, !place.isEmpty, place != was.place, place != ride.location,
           said.contains(where: { RidePlan.place(in: $0.text) != nil || $0.text.localizedCaseInsensitiveContains(place) }) {
            ride.location = place
            ride.latitude = nil; ride.longitude = nil; ride.distanceKm = nil
            notes.append(place)
        }
        guard !notes.isEmpty else { return }
        store.state.events[id] = ride
        if store.decision(id) == .attending { syncCalendar(id) }
        Task { await geocoder.fill(store); store.save() }
        notifyRideChanged(ride.title, change: notes.joined(separator: " · "), chatName: chatName, rideID: id)
    }

    /// Plans to review, once each: a message sent to several chats shows as one plan.
    func openReviews() -> [PlanReview] {
        let open = store.state.reviews.values.filter { $0.status == .open }.sorted { $0.updated > $1.updated || ($0.updated == $1.updated && $0.id < $1.id) }
        return CrossPost.groups(open, same: CrossPost.samePlan).map { $0[0] }
    }

    /// Plans that meet every criterion (see `PlanSummary.readiness`): these are the ones RollCall suggests.
    func possiblePlans() -> [PlanReview] { openReviews().filter { $0.summary.readiness() == .ready } }

    /// Rides being arranged that are still missing a day, time or place. They move up once the chat settles them.
    func partialPlans() -> [PlanReview] {
        openReviews().filter { if case .partial = $0.summary.readiness() { return true } else { return false } }
    }

    /// The other chats the same plan was posted in.
    func crossPosts(_ r: PlanReview) -> [PlanReview] {
        store.state.reviews.values.filter { $0.status == .open && CrossPost.samePlan(r, $0) }.sorted { $0.id < $1.id }
    }

    /// Turns a reviewed plan into a ride, after the user checks the details. Apple Intelligence (when it's on)
    /// reads the conversation first, to fill in as much of the form as it can.
    func addRide(fromReview id: String) {
        guard let r = store.state.reviews[id] else { return }
        let chatName = store.state.feeds.first { $0.id == r.feedID }?.name ?? "a chat"
        ui.readingReview = id
        Task {
            let d = await RideDetails.extract(RideDetails.input(r.lines, chatName: chatName))
            ui.readingReview = nil
            addRide(fromReview: id, details: d, chatName: chatName)
        }
    }

    /// The ride a plan makes: from its summary, what Apple Intelligence read and what Refresh found. `hasTime` is false
    /// when no time was agreed.
    private func planRide(_ r: PlanReview, details d: RideDetails.Details?, chatName: String) -> (form: Dialogs.ManualRide, hasTime: Bool) {
        let s = r.summary
        var start = s.start ?? Dialogs.nextSundayMorning()
        var hasTime = s.hasTime
        // RollCall's own rules read a time written in the messages reliably; otherwise the model's reading is used.
        if let ds = d?.start, !s.hasTime || s.start == nil { start = ds; hasTime = d?.hasTime ?? false }
        if s.start != nil || d?.start != nil, !hasTime { start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: start) ?? start }
        // The plan's own on-device summary already names the ride and place well; the form's reading fills the rest.
        var parts = [s.byAI && !s.summary.isEmpty ? s.summary : d?.details ?? s.calendarNote]
        if let d, !d.stops.isEmpty { parts.append("Stops: " + d.stops.joined(separator: "; ")) }
        if let dest = d?.destination { parts.append("Destination: " + dest) }
        if let l = d?.link { parts.append("Link: " + l) }
        // Where it starts and ends names a chat ride better than "Sam's ride".
        var form = RideEvent(id: r.id, title: RideDetails.routeTitle(from: d?.meet, to: d?.destination) ?? (s.byAI ? s.title : d?.title ?? s.title),
                             start: start, end: start.addingTimeInterval((d?.hours ?? 3) * 3600), allDay: false,
                             location: (s.byAI ? s.place : nil) ?? d?.meet ?? s.place ?? "", notes: parts.joined(separator: "\n"), url: nil,
                             source: "manual", sourceName: chatName, lastSeen: Date())
        // What Refresh found about the plan and you kept.
        let found = keptFindings(r.id)
        for f in found { form = form.applying(RideSearch.edit(form, adding: f)) }
        if found.contains(where: { $0.field == .time }) { hasTime = true }
        let link = Beeper.chatLink(chatID: r.chatID, messageID: r.keyMessage?.id)
        return (.init(title: form.title, start: form.start, hours: (form.end ?? form.finish).timeIntervalSince(form.start) / 3600,
                      location: form.location, link: form.url ?? link, notes: form.notes), hasTime)
    }

    private func addRide(fromReview id: String, details d: RideDetails.Details?, chatName: String) {
        guard let r = store.state.reviews[id] else { return }
        let (form, hasTime) = planRide(r, details: d, chatName: chatName)
        var intro = d != nil ? "Apple Intelligence filled this in from the conversation in \(chatName), on this Mac. Check it before adding."
                             : "From the conversation in \(chatName). Check the time and meeting place."
        if !keptFindings(id).isEmpty { intro += " The details Refresh found are filled in too." }
        guard let ride = Dialogs.manualRide(
            prefill: form,
            note: intro + (hasTime ? "" : " No time was agreed, so 9am is filled in.")) else { return }
        let rideID = keep(r, as: ride, chatName: chatName)
        if Dialogs.confirm("Ride added", "Are you going to “\(ride.title)”?", ok: "Yes, add to calendar") {
            decide(rideID, .attending)
        }
    }

    /// Going, from a plan's notification: adds the ride as the plan gives it, without the form. Opens the plan instead
    /// when it has changed since and isn't complete any more.
    func confirmPlan(_ id: String) async {
        guard let r = store.state.reviews[id], r.status == .open, r.summary.isReady else {
            if let added = store.state.reviews[id]?.rideID { confirmRide(added) } else { openReview(id) }
            return
        }
        let chatName = store.state.feeds.first { $0.id == r.feedID }?.name ?? "a chat"
        let d = await RideDetails.extract(RideDetails.input(r.lines, chatName: chatName))
        // It may have been added or dismissed while that was read.
        guard let now = store.state.reviews[id], now.status == .open else { return }
        var ride = planRide(now, details: d, chatName: chatName).form
        // Meeting where the notification said, unless you've kept a place Refresh found.
        if let place = now.summary.place, !keptFindings(id).contains(where: { $0.field == .place }) { ride.location = place }
        confirmRide(keep(now, as: ride, chatName: chatName))
    }

    /// Keeps a plan as a ride, and returns the ride's id. Only the summary goes in the ride (and so the calendar): the
    /// chat's messages stay in the chat.
    private func keep(_ r: PlanReview, as ride: Dialogs.ManualRide, chatName: String) -> String {
        ui.lookups[r.id] = nil
        let notes = ride.notes
        let item = ICSEvent(uid: "plan-" + stableHash(r.id), title: ride.title, start: ride.start,
                            end: ride.start.addingTimeInterval(ride.hours * 3600), allDay: false, location: ride.location,
                            notes: notes.count > 1500 ? String(notes.prefix(1500)) + "…" : notes,
                            url: ride.link.isEmpty ? nil : ride.link)
        store.merge([item], source: "manual", sourceName: "Chat: " + chatName)
        let rideID = Store.eventID(source: "manual", item: item)
        // Every chat it was posted in, including copies you'd dismissed.
        for other in store.state.reviews.values where other.status != .added && CrossPost.samePlan(r, other) {
            store.state.reviews[other.id]?.status = .added
            store.state.reviews[other.id]?.rideID = rideID
        }
        store.state.reviews[r.id]?.status = .added
        store.state.reviews[r.id]?.rideID = rideID
        store.save()
        Task { await geocoder.fill(store); store.save() }
        updateBadge()
        return rideID
    }

    /// Not a ride: the plan moves to Reviewed, where it stays for as long as Settings → Privacy says.
    func dismissReview(_ id: String) {
        let now = Date()
        for other in (store.state.reviews[id].map(crossPosts) ?? []) + [store.state.reviews[id]].compactMap({ $0 }) {
            store.state.reviews[other.id]?.status = .dismissed
            store.state.reviews[other.id]?.dismissed = now
        }
        store.forgetDismissedMessages(now: now)
        store.save()
        updateBadge()
    }

    /// Puts a dismissed plan back under Possible plans.
    func restoreReview(_ id: String) {
        guard let r = store.state.reviews[id] else { return }
        for other in store.reviewedPlans() where other.id == id || CrossPost.samePlan(r, other) {
            store.state.reviews[other.id]?.status = .open
            store.state.reviews[other.id]?.dismissed = nil
        }
        store.save()
        updateBadge()
    }

    /// Plans you dismissed, once each, for the Reviewed section.
    func reviewedPlans() -> [PlanReview] {
        CrossPost.groups(store.reviewedPlans(), same: CrossPost.samePlan).map { $0[0] }
    }

    /// "Check now" for a single source.
    func checkFeed(_ id: String) async {
        guard let feed = store.state.feeds.first(where: { $0.id == id }) else { return }
        checking.insert(id)
        store.save()
        let changed = await readFeed(feed)
        checking.remove(id)
        store.save()
        await geocoder.fill(store)
        for id in changed where store.decision(id) == .attending { syncCalendar(id) }
        store.save()
        announceNewRides()
        updateBadge()
    }

    func addRecentPosts(_ posts: [PostItem], feed: Feed) {
        guard !posts.isEmpty else { return }
        let cutoff = Date().addingTimeInterval(-Double(Store.maxKeepDays) * 86400)
        var list = posts + (store.state.recentPosts[feed.id] ?? [])
        var seen = Set<String>()
        list = list.filter { seen.insert($0.id).inserted && ($0.published ?? Date()) > cutoff }
        store.state.recentPosts[feed.id] = Array(list.prefix(15))
    }

    /// Ride-related posts with no date found, newest first, that haven't been marked read.
    func postsToLookAt() -> [(feed: Feed, post: PostItem)] {
        let since = store.state.postsReadUntil ?? .distantPast
        return store.state.feeds.flatMap { f in
            (store.state.recentPosts[f.id] ?? []).map { (f, $0) }
        }
        .filter { ($0.post.published ?? Date()) > since }
        .sorted { ($0.post.published ?? .distantPast) > ($1.post.published ?? .distantPast) }
    }

    func scanDownloads(save: Bool = true) {
        guard store.state.settings.watchDownloads else { return }
        let scanStart = Date()
        let files = DownloadsWatcher.newFacebookFiles(since: store.state.lastDownloadsScan)
        store.state.lastDownloadsScan = scanStart
        guard !files.isEmpty else { if save { store.save() }; return }
        let added = importFiles(files, source: "facebook", sourceName: "Facebook")
        if save { store.save() }
        updateBadge()
        if added > 0 {
            notifyImported(added, from: "Facebook")
        }
    }

    @discardableResult
    func importFiles(_ files: [URL], source: String, sourceName: String) -> Int {
        var count = 0
        var changed: [String] = []
        for f in files {
            guard let text = try? String(contentsOf: f, encoding: .utf8) else { continue }
            let items = ICSParser.parse(text)
            count += items.count
            changed += store.merge(items, source: source, sourceName: sourceName)
        }
        for id in changed where store.decision(id) == .attending { syncCalendar(id) }
        Task { await geocoder.fill(store); store.save() }
        return count
    }

    func notifyImported(_ n: Int, from: String) {
        statusItem.button?.title = " +\(n)"
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.updateBadge() }
    }

    func updateBadge() {
        let undecided = store.upcoming().filter { store.decision($0.id) == .undecided }.count + possiblePlans().count
        let hasImage = statusItem.button?.image != nil
        let base = hasImage ? "" : "🏍"
        statusItem.button?.title = undecided > 0 ? "\(base) \(undecided)" : base
        statusItem.button?.toolTip = undecided > 0 ? "\(undecided) ride\(undecided == 1 ? "" : "s") or plan\(undecided == 1 ? "" : "s") to decide on" : "RollCall"
    }
}
