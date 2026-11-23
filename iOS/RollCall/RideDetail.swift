import SwiftUI

/// A ride's page: when and where, whether you're going, its links and what the organiser wrote.
struct RideDetail: View {
    @Environment(PhoneModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    let ride: RideEvent
    @State private var confirmRemove = false

    var body: some View {
        let decision = model.decision(ride.id)
        List {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    DateBadge(date: ride.start, decision: decision, needsCheck: ride.needsCheck == true, scale: 1.4)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ride.title).font(.title2.bold())
                        Text(Format.when(ride)).foregroundStyle(.secondary)
                        if let place = Format.place(ride) { Text(place).foregroundStyle(.secondary) }
                        Text("From \(ride.sourceName)").font(.footnote).foregroundStyle(.tertiary)
                    }
                }
                if ride.needsCheck == true {
                    Label("The date and place were read from a post, so check them before going.", systemImage: "questionmark.circle")
                        .font(.footnote)
                }
            }

            if ride.finish >= Date() {
                Section {
                    Picker("Going?", selection: Binding(get: { decision }, set: { d in Task { await model.decide(ride.id, d) } })) {
                        ForEach(Format.choices, id: \.0) { d, name, _ in Text(name).tag(d) }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    if decision == .attending, ride.isFacebook || ride.url?.contains("meetup.com") == true {
                        Text("It's in your RollCall calendar. To tell the organiser you're coming, press Going on the event page.")
                    }
                }
            }

            Section {
                if let link = ride.url.flatMap(URL.init(string:)) {
                    Button(ride.openLabel, systemImage: "safari") { openURL(link) }
                }
                if ride.hasRoute {
                    Menu {
                        ForEach(MapsApp.allCases.filter { $0 != .automatic }, id: \.self) { app in
                            Button(app.name) { Task { await openRoute(in: app) } }
                        }
                    } label: {
                        Label("Route", systemImage: "map")
                    } primaryAction: {
                        Task { await openRoute(in: nil) }
                    }
                }
            }

            RoutePreview(ride: ride) { Task { await openRoute(in: nil) } }

            if !ride.notes.isEmpty {
                Section("About") {
                    Text(ride.notes).textSelection(.enabled)
                }
            }

            Section {
                Button("Remove Ride", systemImage: "trash", role: .destructive) { confirmRemove = true }
            }
        }
        // Work out the route's start, stops and destination from the description; the map updates once they're found.
        .task(id: Route.fingerprint(ride)) { await model.findRoute(for: ride) }
        .navigationTitle(ride.title)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Remove this ride?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                model.remove(ride.id)
                dismiss()
            }
        } message: {
            Text("It won't come back when its source is checked again.")
        }
    }

    private func openRoute(in app: MapsApp?) async {
        if let url = await model.directions(for: ride, in: app) { openURL(url) }
    }
}
