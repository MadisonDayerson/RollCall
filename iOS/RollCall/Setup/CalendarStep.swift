import SwiftUI
import EventKit

/// Letting RollCall put the rides you're going to in your calendar.
struct CalendarStep: View {
    @Environment(PhoneModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        StepHeader(title: "Your calendar",
                   text: "When you mark a ride Going, RollCall adds it to a calendar called RollCall, with a reminder the evening before, and updates it if the plan changes.")
        Section {
            if model.calendarAllowed {
                DoneLabel(text: "Rides you're going to go in your RollCall calendar")
            } else if [.denied, .restricted, .writeOnly].contains(EKEventStore.authorizationStatus(for: .event)) {
                Text("Calendar access was turned off. In Settings, tap Calendars and choose Full Access, then come back.")
                Button("Open Settings") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
            } else {
                Button("Allow calendar access") { Task { await model.allowCalendar() } }
            }
        } footer: {
            if !model.calendarAllowed { Text("Choose Allow Full Access so RollCall can update rides when plans change.") }
        }
    }
}
