import Foundation
import SwiftUI

extension AppDelegate {
    // MARK: - More details, found by Refresh

    /// At most this many pieces of text are read by the model, a few seconds each.
    static let maxClues = 8

    /// Part of Refresh (not the automatic checks, which run every few minutes): looks for more about the rides you're
    /// going to or might go to, and the plans in To review that have a day. Each one with something new shows it
    /// under More details on its page.
    func findMoreDetails() async {
        guard AppleModel.available else { return }
        let rides = store.upcoming().filter { [.attending, .maybe].contains(store.decision($0.id)) }
        let plans = openReviews().compactMap { r in
            RideSearch.ride(for: r, chatName: store.state.feeds.first { $0.id == r.feedID }?.name ?? "chat")
        }
        // Finds you haven't dealt with yet stay as they are, so ones you left out don't come back.
        for ride in rides + plans where ui.lookups[ride.id] == nil { await findMoreDetails(for: ride) }
    }

    /// Looks for more about one ride in its event page, other listings, posts and your chats (read only, on this Mac),
    /// and keeps what Apple Intelligence agrees is about it and the ride doesn't say yet.
    private func findMoreDetails(for ride: RideEvent) async {
        let id = ride.id
        ui.lookups[id] = .looking("Looking through your sources…")
        let (clues, checked) = await clues(for: ride)
        var found: [RideSearch.Finding] = []
        for (i, clue) in clues.enumerated() {
            ui.lookups[id] = .looking("Checking \(i + 1) of \(clues.count): \(clue.from)…")
            guard let d = await RideSearch.verify(clue, ride: ride) else { continue }
            for f in RideSearch.findings(d, for: ride, from: clue.from) where !found.contains(where: { $0.field == f.field }) {
                found.append(f)
            }
        }
        // Fades in on the ride's page, rather than pushing what you're reading down all at once.
        withAnimation(.easeOut(duration: 0.25)) { ui.lookups[id] = found.isEmpty ? nil : .done(found, checked: checked) }
    }

    /// Adds a found detail to the ride as your own change, like Edit…, and takes it off the list.
    func useFinding(_ f: RideSearch.Finding, rideID id: String) {
        guard let ride = store.state.events[id] else { return }
        saveEdit(RideSearch.edit(ride, adding: f), to: ride)
        leaveOut(f, from: id)
    }

    func leaveOut(_ f: RideSearch.Finding, from id: String) {
        if case .done(let left, let checked) = ui.lookups[id] {
            ui.lookups[id] = .done(left.filter { $0 != f }, checked: checked)
        }
    }

    /// The details found for a plan that you kept, to fill in its Add ride form.
    func keptFindings(_ id: String) -> [RideSearch.Finding] {
        if case .done(let found, _) = ui.lookups[id] { return found }
        return []
    }

    /// Text that might be about the ride, best first, and what was looked through.
    private func clues(for ride: RideEvent) async -> ([RideSearch.Clue], String) {
        let mine = Set(([ride] + store.copies(of: ride)).map(\.id))
        var clues: [RideSearch.Clue] = []
        var checked: [String] = []

        // The ride's own event pages (never Facebook or Instagram, which RollCall doesn't read).
        let pages = ([ride] + store.copies(of: ride)).compactMap(\.url).uniqued().filter { u in
            u.hasPrefix("http") && !["facebook.com", "fb.me", "instagram.com", "beeper"].contains { u.contains($0) }
        }
        for page in pages {
            guard let html = try? await Web.get(page).text else { continue }
            let text = String(Web.plainText(html).prefix(5000))
            if !text.isEmpty { clues.append(.init(from: "the event page", input: .init(heading: "Event page", lines: [text]))) }
        }
        if !pages.isEmpty { checked.append(pages.count == 1 ? "its event page" : "its event pages") }

        // Your chats: the last two weeks of each, with the replies after anything that mentions the ride.
        let chats = store.state.feeds.filter { $0.type == .chat }
        if !chats.isEmpty {
            if await Beeper.isRunning() {
                let since = Date().addingTimeInterval(-Double(Store.maxKeepDays) * 86400)
                for chat in chats {
                    let chatID = Beeper.chatID(of: chat)
                    guard let messages = try? await Beeper.messages(chatID: chatID, since: since, maxPages: 20) else { continue }
                    let lines = messages.compactMap { m in SourceReader.chatPost(m, chatID: chatID).map { PlanFinder.line(from: $0, sender: SourceReader.chatSender(m)) } }
                    let picked = RideSearch.aboutRide(lines, ride)
                    if !picked.isEmpty { clues.append(.init(from: chat.name, input: RideDetails.input(picked, chatName: chat.name))) }
                }
                checked.append(chats.count == 1 ? "your chat" : "your \(chats.count) chats")
            } else {
                checked.append("not your chats (Beeper isn't open)")
            }
        }

        // The same day's rides from your other sources, and their posts without a date.
        for e in store.state.events.values where !mine.contains(e.id) && Calendar.current.isDate(e.start, inSameDayAs: ride.start) {
            let text = [e.title, e.location, e.notes].filter { !$0.isEmpty }.joined(separator: "\n")
            if RideSearch.mightBeAbout(text, ride) { clues.append(.init(from: e.sourceName, input: .init(heading: "Listing", lines: [text]))) }
        }
        for feed in store.state.feeds {
            for post in store.state.recentPosts[feed.id] ?? [] where RideSearch.mightBeAbout(post.title + "\n" + post.text, ride) {
                clues.append(.init(from: feed.name, input: .init(heading: "Post", lines: [post.text])))
            }
        }
        checked.append("your other sources")
        return (Array(clues.prefix(Self.maxClues)), checked.joined(separator: ", "))
    }
}
