import Foundation
import EventKit

/// Keeps a "RollCall" calendar in step with the rides marked Attending. It lives in whichever account
/// the person picks in setup: iCloud (Apple Calendar), Google (added in Internet Accounts), Exchange or this Mac.
@MainActor
final class CalendarSync {
    static let calendarTitle = "RollCall"
    static let oldTitle = "Moto Rides"
    /// EventKit source to hold the calendar; nil picks iCloud, then the default account.
    var preferredSourceID: String?
    let eventStore = EKEventStore()
    private(set) var authorised = false

    /// Notes whether access was already given, without asking.
    func checkAccess() {
        authorised = EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    func requestAccess() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .fullAccess { authorised = true; return true }
        if status == .denied || status == .restricted { authorised = false; return false }
        authorised = (try? await eventStore.requestFullAccessToEvents()) ?? false
        return authorised
    }

    /// Calendar accounts that can hold a new calendar, for setup to offer.
    func accounts() -> [EKSource] {
        eventStore.refreshSourcesIfNecessary()
        let kinds: [EKSourceType] = [.calDAV, .exchange, .local]
        return eventStore.sources.filter { s in
            kinds.contains(s.sourceType) && s.title.lowercased() != "other"
                && (s.sourceType == .local || !s.calendars(for: .event).isEmpty)
        }
    }

    /// The RollCall calendar if it exists, in the chosen account when one is set.
    func existingCalendar() -> EKCalendar? {
        let mine = eventStore.calendars(for: .event).filter {
            ($0.title == Self.calendarTitle || $0.title == Self.oldTitle) && $0.allowsContentModifications
        }
        if let id = preferredSourceID { return mine.first { $0.source.sourceIdentifier == id } }
        return mine.first
    }

    /// Finds or creates the RollCall calendar, preferring iCloud so rides show on the phone too.
    func rideCalendar() throws -> EKCalendar {
        if let c = existingCalendar() {
            if c.title == Self.oldTitle {
                // Named before the app became RollCall.
                c.title = Self.calendarTitle
                try? eventStore.saveCalendar(c, commit: true)
            }
            return c
        }
        let cal = EKCalendar(for: .event, eventStore: eventStore)
        cal.title = Self.calendarTitle
        cal.cgColor = CGColor(red: 0.95, green: 0.45, blue: 0.1, alpha: 1)
        let sources = eventStore.sources
        cal.source = preferredSourceID.flatMap { id in sources.first { $0.sourceIdentifier == id } }
            ?? sources.first { $0.sourceType == .calDAV && $0.title.lowercased().contains("icloud") }
            ?? eventStore.defaultCalendarForNewEvents?.source
            ?? sources.first { $0.sourceType == .local }
        guard cal.source != nil else { throw SyncError.noCalendarAccount }
        try eventStore.saveCalendar(cal, commit: true)
        return cal
    }

    /// Adds or updates the ride in Apple Calendar. Returns the calendar item id to remember.
    func upsert(_ ride: RideEvent, existingID: String?, crewCard: [String] = []) throws -> String {
        let cal = try rideCalendar()
        let ev = existingID.flatMap { eventStore.calendarItem(withIdentifier: $0) as? EKEvent }
            ?? EKEvent(eventStore: eventStore)
        ev.calendar = cal
        ev.title = ride.title
        ev.startDate = ride.start
        ev.isAllDay = ride.allDay
        if ride.allDay {
            ev.endDate = ride.end.map { $0.addingTimeInterval(-1) } ?? ride.start
        } else {
            ev.endDate = ride.end ?? ride.start.addingTimeInterval(4 * 3600)
        }
        ev.location = ride.location.isEmpty ? nil : ride.location
        ev.url = ride.url.flatMap(URL.init(string:))
        var notes = "From \(ride.sourceName) via RollCall."
        if !crewCard.isEmpty { notes += "\n\n" + crewCard.joined(separator: "\n") }
        // A ride read straight from a chat message keeps that message in RollCall, not in the calendar.
        if !ride.notes.isEmpty && !ride.source.hasPrefix("beeper-") { notes += "\n\n" + ride.notes }
        ev.notes = notes
        if ev.alarms?.isEmpty ?? true, !ride.allDay {
            ev.addAlarm(EKAlarm(relativeOffset: -12 * 3600))  // the evening before: check the bike
        }
        try eventStore.save(ev, span: .thisEvent, commit: true)
        return ev.calendarItemIdentifier
    }

    func remove(itemID: String) {
        guard let ev = eventStore.calendarItem(withIdentifier: itemID) as? EKEvent else { return }
        try? eventStore.remove(ev, span: .thisEvent, commit: true)
    }
}

enum SyncError: LocalizedError {
    case noCalendarAccount
    var errorDescription: String? { "No calendar account was found to hold the RollCall calendar." }
}
