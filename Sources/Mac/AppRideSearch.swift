import Foundation
import SwiftUI

extension AppDelegate {
    // MARK: - More details, found by Refresh

    /// Part of Refresh (not the automatic checks, which run every few minutes): looks for more about the rides you're
    /// going to or might go to, and the plans in To review that have a day. Each one with something new shows it
    /// under More details on its page.
    func findMoreDetails() async {
        guard AppleModel.available else { return }
        // Finds you haven't dealt with yet stay as they are, so ones you left out don't come back.
        for ride in detailsToFind() where ui.lookups[ride.id] == nil {
            let id = ride.id
            withAnimation(.easeOut(duration: 0.2)) { ui.lookups[id] = .starting }
            let (found, checked) = await moreDetails(for: ride) { self.ui.lookups[id] = .looking($0) }
            // Fades in on the ride's page, rather than pushing what you're reading down all at once.
            withAnimation(.easeOut(duration: 0.25)) { ui.lookups[id] = found.isEmpty ? nil : .done(found, checked: checked) }
        }
    }

    /// The rides you're going to or might go to, and the plans in To review that have a day.
    func detailsToFind() -> [RideEvent] {
        let plans = openReviews().compactMap { r in
            RideSearch.ride(for: r, chatName: store.state.feeds.first { $0.id == r.feedID }?.name ?? "chat")
        }
        return store.ridesWantingDetails() + plans
    }

    /// Looks for more about one ride in its event page, other listings, posts and your chats (read only, on this Mac).
    func moreDetails(for ride: RideEvent, progress: (String) -> Void = { _ in }) async -> ([RideSearch.Finding], checked: String) {
        await store.moreDetails(for: ride, chats: await chatClues(for: ride), progress: progress)
    }

    /// Adds a found detail to the ride as your own change, like Edit…, and takes it off the list.
    func useFinding(_ f: RideSearch.Finding, rideID id: String) {
        guard let ride = store.state.events[id] else { return }
        saveEdit(RideSearch.edit(ride, adding: f), to: ride)
        leaveOut(f, from: id)
    }

    func leaveOut(_ f: RideSearch.Finding, from id: String) {
        ui.lookups[id] = ui.lookups[id]?.without(f)
    }

    /// The details found for a plan that you kept, to fill in its Add ride form.
    func keptFindings(_ id: String) -> [RideSearch.Finding] {
        if case .done(let found, _) = ui.lookups[id] { return found }
        return []
    }

    /// What your chats say that might be about the ride: the last two weeks of each, with the replies after anything
    /// that mentions it. The chat a ride or plan came from is read for its day as well as its name.
    private func chatClues(for ride: RideEvent) async -> (clues: [RideSearch.Clue], checked: String?) {
        let chats = store.state.feeds.filter { $0.type == .chat }
        guard !chats.isEmpty else { return ([], nil) }
        guard await Beeper.isRunning() else { return ([], "not your chats (Beeper isn't open)") }
        // A ride added from a plan links to its chat, which outlasts the plan itself.
        let copies = [ride] + store.copies(of: ride)
        let ownChatIDs = Set(copies.compactMap { $0.url.flatMap(Beeper.chatParts)?.chat })
        let ownChats = Set(chats.filter { ownChatIDs.contains(Beeper.chatID(of: $0)) }.map(\.id) + copies.map(\.source))
        let since = Date().addingTimeInterval(-Double(Store.maxKeepDays) * 86400)
        var clues: [RideSearch.Clue] = []
        for chat in chats {
            let chatID = Beeper.chatID(of: chat)
            guard let messages = try? await Beeper.messages(chatID: chatID, since: since, maxPages: 20) else { continue }
            let lines = messages.compactMap { m in SourceReader.chatPost(m, chatID: chatID).map { PlanFinder.line(from: $0, sender: SourceReader.chatSender(m)) } }
            let picked = RideSearch.aboutRide(lines, ride, ownChat: ownChats.contains(chat.id))
            if !picked.isEmpty { clues.append(.init(from: chat.name, input: RideDetails.input(picked, chatName: chat.name))) }
        }
        return (clues, chats.count == 1 ? "your chat" : "your \(chats.count) chats")
    }
}
