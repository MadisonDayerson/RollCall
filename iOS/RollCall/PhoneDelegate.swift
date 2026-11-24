import UIKit
import UserNotifications

/// Holds the model, so a notification answered while RollCall is closed reaches it before any screen is made.
final class PhoneDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let model = PhoneModel()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        RideNotice.setUp(self)
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler done: @escaping () -> Void) {
        let reply = RideNotice.reply(button: response.actionIdentifier, info: response.notification.request.content.userInfo)
        DispatchQueue.main.async {
            MainActor.assumeIsolated { if let reply { self.model.answer(reply) } }
            done()
        }
    }

    /// Shown while RollCall is open too.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .list, .sound])
    }
}
