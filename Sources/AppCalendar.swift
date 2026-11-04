import AppKit
import SwiftUI

extension AppDelegate {
    // MARK: - Decisions and calendar

    func decide(_ id: String, _ d: Decision) {
        store.state.decisions[id] = d
        syncCalendar(id)
        store.save()
        updateBadge()
        if d == .attending, let ride = store.state.events[id], ride.url != nil,
           ride.isFacebook || ride.url!.contains("meetup.com") {
            // Facebook and Meetup only count you in when you press Going there yourself.
            if Dialogs.confirm("Added to your calendar",
                               "“\(ride.title)” is in your RollCall calendar.\n\nTo tell the organiser you're coming, open the event page and press Going (Facebook) or Attend (Meetup).",
                               ok: "Open event page") {
                open(ride.url)
            }
        }
    }

    /// Takes a finished ride off Past rides; the calendar event stays, as a record of the day.
    func forgetPastRide(_ id: String) {
        store.state.decisions[id] = nil
        store.state.calendarItems[id] = nil
        store.prune(refreshedSources: [], refreshStarted: Date())
        store.save()
        NotificationCenter.default.post(name: Store.changed, object: nil)
    }

    func syncCalendar(_ id: String) {
        let attending = store.decision(id) == .attending
        let existing = store.state.calendarItems[id]
        if attending, let ride = store.state.events[id] {
            guard calendar.authorised else {
                Dialogs.info("Calendar access needed",
                             "RollCall isn't allowed to add events to Calendar yet.\n\nOpen System Settings → Privacy & Security → Calendars, and switch on RollCall (choose Full Access). Then mark the ride Going again.")
                return
            }
            do {
                store.state.calendarItems[id] = try calendar.upsert(ride, existingID: existing, crewCard: crewCard(ride))
            } catch {
                Dialogs.info("Couldn't add to Calendar", error.localizedDescription)
            }
        } else if let existing {
            calendar.remove(itemID: existing)
            store.state.calendarItems[id] = nil
        }
    }

    // MARK: - Riding together

    func links(_ ride: RideEvent) -> CrewLinks? { store.state.crew[Crew.key(forSource: ride.source)] }
    func crewCard(_ ride: RideEvent) -> [String] {
        Crew.card(ride, together: store.state.settings.crew, links: links(ride))
    }
    func setTogether(_ t: Together) {
        guard t != store.state.settings.crew else { return }
        store.state.settings.together = t
        resyncCalendar()
        store.save()
    }

    func setCrewLinks(_ key: String, _ l: CrewLinks) {
        let clean = CrewLinks(discord: l.discord?.trimmingCharacters(in: .whitespaces).nilIfEmpty,
                              tags: l.tags?.trimmingCharacters(in: .whitespaces).nilIfEmpty)
        guard clean != store.state.crew[key] ?? CrewLinks() else { return }
        store.state.crew[key] = clean == CrewLinks() ? nil : clean
        resyncCalendar()
        store.save()
    }

    /// Rewrites the crew details on calendar events for rides you're going to.
    /// Rides added from chats used to carry the conversation in their notes, and that went into the calendar.
    /// Swaps it for the plan's summary, and updates calendar events from chats so they leave the messages out.
    func tidyChatNotes() {
        var changed: [String] = []
        for (id, var e) in store.state.events where id.hasPrefix("manual:plan-") && e.notes.contains("\n") {
            let review = store.state.reviews.values.first { $0.rideID == id }
            let first = e.notes.components(separatedBy: "\n")[0]
            e.notes = review?.summary.calendarNote ?? (first.contains(" wrote: “") ? "" : first)
            store.state.events[id] = e
            changed.append(id)
        }
        changed += store.state.events.keys.filter { $0.hasPrefix("beeper-") }
        if !changed.isEmpty { store.save() }
        for id in changed where store.decision(id) == .attending && store.state.calendarItems[id] != nil { syncCalendar(id) }
    }

    func resyncCalendar() {
        guard calendar.authorised else { return }
        for (id, d) in store.state.decisions where d == .attending && store.state.calendarItems[id] != nil { syncCalendar(id) }
    }
}
