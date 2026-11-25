import SwiftUI

/// A ride's page: when and where, whether you're going, its links and what the organiser wrote.
struct RideDetail: View {
    @Environment(PhoneModel.self) private var model
    @Environment(\.openURL) private var openURL
    let ride: RideEvent
    /// Leaves the page, once its ride is removed.
    let close: () -> Void
    @State private var confirmRemove = false

    var body: some View {
        let decision = model.decision(ride.id)
        let past = ride.finish < Date()
        List {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    DateBadge(date: ride.start, decision: decision, needsCheck: ride.needsCheck == true, past: past, scale: 1.4)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ride.title).font(.title2.bold())
                        Text(Format.when(ride, end: true)).foregroundStyle(.secondary)
                        if let place = Format.place(ride) { Text(place).foregroundStyle(.secondary) }
                        if let note = model.store.meetingNote(ride) { Text(note).font(.footnote).foregroundStyle(.secondary) }
                        Text(model.sourceLine(ride)).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if ride.needsCheck == true {
                    Label {
                        Text("The date and place were read from a post or message. Check them before going.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    }
                    .font(.footnote)
                }
            }

            if past {
                Section { Label("You went", systemImage: "checkmark.seal").listItemTint(.primary) }
            } else {
                Section {
                    DecisionPicker(decision: decision) { d in Task { await model.decide(ride.id, d) } }
                } footer: {
                    if decision == .attending, ride.isFacebook || ride.url?.contains("meetup.com") == true {
                        Text((model.state.calendarItems[ride.id] == nil ? "" : "It's in your RollCall calendar. ")
                             + "To tell the organiser you're coming, press Going on the event page.")
                    } else {
                        Text("Going adds it to the RollCall calendar, with a reminder the evening before.")
                    }
                }
            }

            Section {
                // Chats are only on the Mac, so a chat ride's link opens there.
                let link = Web.link(ride.url)
                let chat = ride.url.flatMap(Beeper.chatParts) != nil
                Button(ride.openLabel + (chat ? " (on your Mac)" : ""), systemImage: "safari") { if let link { openURL(link) } }
                    .modifier(RowAction(available: link != nil))
                Menu {
                    if Route.link(in: ride.notes) != nil {
                        Button("Organiser's route") { Task { await openRoute(in: nil) } }
                        Divider()
                    }
                    ForEach(MapsApp.allCases.filter { $0 != .automatic }, id: \.self) { app in
                        Button(app.title(for: ride)) { Task { await openRoute(in: app) } }
                    }
                } label: {
                    Label(ride.hasRoute ? "Open route in" : "Open route in (no place)", systemImage: "map")
                }
                .modifier(RowAction(available: ride.hasRoute))
            }

            if !ride.notes.isEmpty { RideAbout(ride: ride).id(ride.id) }

            if let lookup = model.lookups[ride.id] { RideFindings(id: ride.id, lookup: lookup) }

            RoutePreview(ride: ride) { Task { await openRoute(in: nil) } }

            Section {
                Button(past ? "Remove from past rides…" : "Remove…", systemImage: "trash", role: .destructive) { confirmRemove = true }
                    .listItemTint(.red)
            }
        }
        // Work out the route's start, stops and destination from the description; the map updates once they're found.
        .task(id: Route.fingerprint(ride)) { await model.findRoute(for: ride) }
        .confirmationDialog("Remove this ride?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                model.remove(ride)
                close()
            }
        } message: {
            Text(past ? "Its calendar event stays." : "It won't come back when its source is checked again.")
        }
    }

    private func openRoute(in app: MapsApp?) async {
        if let url = await model.directions(for: ride, in: app) { openURL(url) }
    }
}

/// A row that does something, greyed out when it can't (a row's icon otherwise keeps its blue).
private struct RowAction: ViewModifier {
    let available: Bool

    func body(content: Content) -> some View {
        let color: Color = available ? .accentColor : .secondary
        content.listItemTint(.fixed(color)).foregroundStyle(color).disabled(!available)
    }
}
