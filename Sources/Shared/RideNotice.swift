import Foundation
import UserNotifications

/// The notifications about rides, worded the same on the Mac, iPhone and iPad, and what tapping them means.
enum RideNotice {
    /// Notifications with the Going and Review buttons.
    static let category = "ride"
    private static let goingButton = "going", reviewButton = "review"
    /// More new rides than this at once make one notification.
    static let mostAtOnce = 3

    /// What you chose on a notification.
    enum Reply: Equatable {
        case going(String), review(String), list
    }

    static func setUp(_ delegate: UNUserNotificationCenterDelegate) {
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        center.setNotificationCategories([UNNotificationCategory(
            identifier: category,
            // Going is done without opening RollCall; Review opens it.
            actions: [UNNotificationAction(identifier: goingButton, title: "Going", options: []),
                      UNNotificationAction(identifier: reviewButton, title: "Review", options: [.foreground])],
            intentIdentifiers: [], options: [])])
    }

    /// Tells you about rides that weren't here before, and clears the notifications of ones decided since (here or on
    /// another device). Returns whether there's something to save.
    @MainActor static func announce(_ store: Store) -> Bool {
        guard store.state.setupDone, !Store.picturesOnly, Bundle.main.bundleIdentifier != nil else { return false }
        let before = store.state.knownRides
        let new = store.newRides()
        if new.count > mostAtOnce {
            send(several(new), id: "new-rides")
        } else {
            for ride in new { send(Self.new(ride), id: newID(ride.id)) }
        }
        let decided = store.state.decisions.filter { $0.value != .undecided }.keys
        let gone = decided.map(newID) + store.state.removedRides.keys.map(newID)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: gone)
        return store.state.knownRides != before
    }

    /// Marks a ride Going from its notification, and says how that went.
    @MainActor static func confirm(_ id: String, in store: Store, using calendar: CalendarSync) {
        guard let ride = store.state.events[id] else {
            send(missing(), id: "missing-" + id)
            return
        }
        store.state.decisions[id] = .attending
        calendar.checkAccess()
        let added = (try? store.syncCalendar(id, using: calendar)) != nil
        send(going(ride, inCalendar: added), id: "going-" + id)
    }

    static func send(_ content: UNNotificationContent, id: String) {
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    /// Takes away every notification, when all data is deleted.
    static func clear() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    private static func newID(_ ride: String) -> String { "new-" + ride }

    // MARK: - What they say

    static func new(_ ride: RideEvent) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        c.title = "New ride: " + ride.title
        c.subtitle = ride.sourceName
        c.body = details(ride)
        if ride.needsCheck == true { c.body += "\nThe date and place were read from a post, so check them before going." }
        c.sound = .default
        c.categoryIdentifier = category
        c.userInfo = ["ride": ride.id]
        return c
    }

    static func several(_ rides: [RideEvent]) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        c.title = "\(rides.count) new rides"
        c.body = rides.prefix(mostAtOnce).map(\.title).joined(separator: "\n") + "\nand \(rides.count - mostAtOnce) more"
        c.sound = .default
        c.userInfo = ["rides": rides.count]
        return c
    }

    /// Answers Going, which otherwise leaves nothing to see.
    static func going(_ ride: RideEvent, inCalendar: Bool) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        c.title = "You're going: " + ride.title
        c.body = details(ride) + "\n" + (inCalendar ? "It's in your RollCall calendar."
                                          : "It isn't in your calendar yet: RollCall needs access. Open Settings → Run setup… and go to Calendar.")
        if ride.isFacebook || ride.url?.contains("meetup.com") == true {
            c.body += " To tell the organiser you're coming, press Going on the event page."
        }
        c.userInfo = ["ride": ride.id]
        return c
    }

    private static func missing() -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        c.title = "That ride isn't listed any more"
        c.body = "Its source dropped it, or it was removed."
        c.userInfo = ["rides": 0]
        return c
    }

    private static func details(_ ride: RideEvent) -> String {
        let km = ride.distanceKm.map { "\(Int($0.rounded())) km away" }
        return [PlanFinder.describe(ride.start, hasTime: !ride.allDay), ride.location.nilIfEmpty, km].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: - What you chose

    /// `button` is the one pressed, or the notification itself.
    static func reply(button: String, info: [AnyHashable: Any]) -> Reply? {
        if let ride = info["ride"] as? String { return button == goingButton ? .going(ride) : .review(ride) }
        return info["rides"] == nil ? nil : .list
    }

    static func isGoing(_ button: String) -> Bool { button == goingButton }
}
