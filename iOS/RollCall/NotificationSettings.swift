import SwiftUI

/// Whether notifications are on, and the button that turns them on, for setup and Settings.
struct NotificationSettings: View {
    @Environment(PhoneModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        switch model.notificationsAllowed {
        case true?:
            DoneLabel(text: "RollCall tells you about new rides")
        case false?:
            Text("Notifications are off. In Settings, tap Notifications and turn on Allow Notifications, then come back.")
            Button("Open Settings") { openURL(URL(string: UIApplication.openNotificationSettingsURLString)!) }
        case nil:
            Button("Allow notifications") { Task { await model.allowNotifications() } }
        }
    }
}
