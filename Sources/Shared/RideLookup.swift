import Foundation

/// Refresh's search for more details about your rides. The Mac and iPhone apps look the same way; the Mac also gives
/// what your chats say (they're only read there).
extension RideSearch {
    /// What a ride's page shows about the search: what it's checking now, then what it found.
    enum Lookup {
        case looking(String)
        case done([Finding], checked: String)

        /// Before anything has been checked.
        static let starting = Lookup.looking("Looking through your sources…")

        /// What's left once you've added a find or left it out.
        func without(_ f: Finding) -> Lookup {
            guard case .done(let found, let checked) = self else { return self }
            return .done(found.filter { $0 != f }, checked: checked)
        }
    }

    /// At most this many pieces of text are read by the model, a few seconds each.
    static let maxClues = 8
}

@MainActor
extension Store {
    /// The rides Refresh looks for more details about: the ones you're going to or might go to.
    func ridesWantingDetails() -> [RideEvent] {
        upcoming().filter { [.attending, .maybe].contains(decision($0.id)) }
    }

    /// Looks for more about one ride in its event page, what `chats` gives, and other listings and posts, and keeps
    /// what Apple Intelligence agrees is about it and the ride doesn't say yet. Also says what was looked through.
    func moreDetails(for ride: RideEvent, chats: (clues: [RideSearch.Clue], checked: String?) = ([], nil),
                     progress: (String) -> Void) async -> ([RideSearch.Finding], checked: String) {
        let pages = await pageClues(for: ride)
        let clues = (pages.clues + chats.clues + listingClues(for: ride)).prefix(RideSearch.maxClues)
        var found: [RideSearch.Finding] = []
        for (i, clue) in clues.enumerated() {
            progress("Checking \(i + 1) of \(clues.count): \(clue.from)…")
            guard let d = await RideSearch.verify(clue, ride: ride) else { continue }
            for f in RideSearch.findings(d, for: ride, from: clue.from) where !found.contains(where: { $0.field == f.field }) {
                found.append(f)
            }
        }
        return (found, [pages.checked, chats.checked, "your other sources"].compactMap { $0 }.joined(separator: ", "))
    }

    /// The ride's own event pages (never Facebook or Instagram, which RollCall doesn't read).
    private func pageClues(for ride: RideEvent) async -> (clues: [RideSearch.Clue], checked: String?) {
        let pages = ([ride] + copies(of: ride)).compactMap(\.url).uniqued().filter { u in
            u.hasPrefix("http") && !["facebook.com", "fb.me", "instagram.com", "beeper"].contains { u.contains($0) }
        }
        var clues: [RideSearch.Clue] = []
        for page in pages {
            guard let html = try? await Web.get(page).text else { continue }
            let text = String(Web.plainText(html).prefix(5000))
            if !text.isEmpty { clues.append(.init(from: "the event page", input: .init(heading: "Event page", lines: [text]))) }
        }
        return (clues, pages.isEmpty ? nil : pages.count == 1 ? "its event page" : "its event pages")
    }

    /// The same day's rides from your other sources, and their posts without a date.
    func listingClues(for ride: RideEvent) -> [RideSearch.Clue] {
        let mine = Set(([ride] + copies(of: ride)).map(\.id))
        var clues: [RideSearch.Clue] = []
        for e in state.events.values where !mine.contains(e.id) && Calendar.current.isDate(e.start, inSameDayAs: ride.start) {
            let text = [e.title, e.location, e.notes].filter { !$0.isEmpty }.joined(separator: "\n")
            if RideSearch.mightBeAbout(text, ride) { clues.append(.init(from: e.sourceName, input: .init(heading: "Listing", lines: [text]))) }
        }
        for feed in state.feeds {
            for post in state.recentPosts[feed.id] ?? [] where RideSearch.mightBeAbout(post.title + "\n" + post.text, ride) {
                clues.append(.init(from: feed.name, input: .init(heading: "Post", lines: [post.text])))
            }
        }
        return clues
    }
}
