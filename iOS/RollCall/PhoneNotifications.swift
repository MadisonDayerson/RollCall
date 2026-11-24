import SwiftUI
import UserNotifications
import BackgroundTasks

/// Notifications about new rides, and the checks for them while RollCall is closed.
extension PhoneModel {
    static let backgroundCheck = "au.madiday.rollcall.ios.check"

    // MARK: - Permission

    /// Notes whether notifications are allowed (nil when you haven't been asked), which can change in the Settings app.
    func checkNotifications() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        notificationsAllowed = status == .notDetermined ? nil : status != .denied
    }

    func allowNotifications() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        await checkNotifications()
    }

    // MARK: - Answering

    /// Does what you chose on a notification: marks the ride Going without opening RollCall, or opens its page.
    func answer(_ reply: RideNotice.Reply) {
        switch reply {
        case .going(let id):
            RideNotice.confirm(id, in: store, using: calendar)
            saved()
        case .review(let id):
            show(.rides)
            rideToOpen = id
        case .list: show(.rides)
        }
    }

    private func show(_ tab: PhoneTab) {
        settingUp = false
        self.tab = tab
    }

    // MARK: - While RollCall is closed

    /// Asks for a check in an hour or more; iOS picks when, from how often RollCall is opened and the battery.
    func scheduleCheck() {
        guard state.setupDone else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundCheck)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Takes in the Mac's changes, then reads the sources that are due. iOS gives it about half a minute.
    func checkInBackground() async {
        scheduleCheck()
        guard state.setupDone else { return }
        shareNow()
        await refresh(dueOnly: true)
    }
}
