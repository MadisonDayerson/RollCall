import SwiftUI

/// Letting RollCall tell you about new rides.
struct NotificationsStep: View {
    var body: some View {
        StepHeader(title: "New rides",
                   text: "RollCall can notify you when it finds a new ride. Touch and hold the notification to choose Going, which puts it straight in your calendar, or Review, which opens it here.")
        Section {
            NotificationSettings()
        } footer: {
            Text("RollCall checks your sources now and then while it's closed. iOS decides when, so a new ride can take a few hours to show up.")
        }
    }
}
