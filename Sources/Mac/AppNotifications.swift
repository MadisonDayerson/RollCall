import AppKit
import UserNotifications

extension AppDelegate {
    // MARK: - Notifications

    /// Tells you about rides from your sources that weren't here before.
    func announceNewRides() {
        guard store.state.setupDone, !Store.picturesOnly, Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        // Asks before the first one; setup's last page has usually asked already.
        if store.state.knownRides == nil { center.requestAuthorization(options: [.alert, .sound]) { _, _ in } }
        if RideNotice.announce(store) { store.save() }
        // Plans dealt with since.
        center.removeDeliveredNotifications(withIdentifiers: store.state.reviews.values.filter { $0.status != .open }.map(\.id))
    }

    /// Tells you about a plan in a chat that's complete: Going adds it as a ride, Review opens it.
    func notify(_ r: PlanReview, chatName: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = "Possible ride plan: " + r.summary.title
        content.subtitle = chatName
        content.body = [r.summary.when, r.summary.place].compactMap { $0 }.joined(separator: " · ")
        content.sound = .default
        content.categoryIdentifier = RideNotice.category
        content.userInfo = ["review": r.id]
        RideNotice.send(content, id: r.id)
    }

    func notifyRideChanged(_ title: String, change: String, chatName: String, rideID: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = "Ride updated: " + title
        content.subtitle = "From the conversation in " + chatName
        content.body = change
        content.userInfo = ["ride": rideID]
        RideNotice.send(content, id: "ride-" + rideID)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler done: @escaping () -> Void) {
        let button = response.actionIdentifier
        let info = response.notification.request.content.userInfo
        let reply = RideNotice.reply(button: button, info: info)
        let review = info["review"] as? String
        let isUpdate = info["update"] != nil
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if isUpdate { self.updateMenu() }
                else if let review { self.answer(review: review, going: RideNotice.isGoing(button)) }
                else if let reply { self.answer(reply) }
            }
        }
        done()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound])
    }

    private func answer(_ reply: RideNotice.Reply) {
        switch reply {
        case .going(let id): confirmRide(id)
        case .review(let id):
            ui.reveal(ride: id)
            showWindow()
        case .list: showWindow(page: .rides)
        }
    }

    private func answer(review id: String, going: Bool) {
        if going { Task { await confirmPlan(id) } } else { openReview(id) }
    }

    /// Going, from a notification: in the calendar without opening the window, and a notification says so.
    func confirmRide(_ id: String) {
        RideNotice.confirm(id, in: store, using: calendar)
        store.save()
        updateBadge()
        syncDevices()
    }

    func openReview(_ id: String) {
        ui.selectedReview = id
        showWindow(page: .review)
    }
}
