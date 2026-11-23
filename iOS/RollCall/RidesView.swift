import SwiftUI

/// Upcoming rides in Undecided, Going, Skipped and Past, with each ride's details beside the list on iPad.
struct RidesView: View {
    @Environment(PhoneModel.self) private var model
    @State private var selected: String?

    var body: some View {
        NavigationSplitView {
            List(selection: $selected) {
                ForEach(model.sections) { section in
                    if !section.rides.isEmpty {
                        Section {
                            ForEach(section.rides, id: \.id) { ride in
                                RideRow(ride: ride, past: section.name == "Past").tag(ride.id)
                            }
                        } header: {
                            PatchLabel(text: section.name, count: section.rides.count)
                        }
                    }
                }
            }
            .navigationTitle("Rides")
            .refreshable { await model.refresh() }
            .overlay { if model.sections.allSatisfy(\.rides.isEmpty) { empty } }
            .toolbar {
                if model.refreshing { ToolbarItem { ProgressView() } }
            }
        } detail: {
            if let id = selected, let ride = model.state.events[id] {
                RideDetail(ride: ride)
            } else {
                ContentUnavailableView("Choose a ride", systemImage: "motorcycle")
            }
        }
    }

    private var empty: some View {
        ContentUnavailableView {
            Label(model.refreshing ? "Checking your sources…" : "No rides yet", systemImage: "motorcycle")
        } description: {
            Text(model.refreshing ? "Rides appear here as they're found." : "Pull down to check your sources, or add more under Sources.")
        }
    }
}

/// One ride in the list: its date patch, name, time and place. Swipe for Going or Skip.
struct RideRow: View {
    @Environment(PhoneModel.self) private var model
    let ride: RideEvent
    var past = false

    var body: some View {
        let decision = model.decision(ride.id)
        HStack(spacing: 12) {
            DateBadge(date: ride.start, decision: decision, needsCheck: ride.needsCheck == true, past: past)
            VStack(alignment: .leading, spacing: 3) {
                Text(ride.title).font(.headline).lineLimit(2)
                Text(Format.when(ride)).font(.subheadline).foregroundStyle(.secondary)
                if let place = Format.place(ride) {
                    Text(place).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .leading) {
            if !past {
                Button(decision == .attending ? "Undecided" : "Going", systemImage: decision == .attending ? "arrow.uturn.backward" : "checkmark") {
                    Task { await model.decide(ride.id, decision == .attending ? .undecided : .attending) }
                }
                .tint(decision == .attending ? .gray : .green)
            }
        }
        .swipeActions(edge: .trailing) {
            if !past {
                Button(decision == .skip ? "Undecided" : "Skip", systemImage: decision == .skip ? "arrow.uturn.backward" : "xmark") {
                    Task { await model.decide(ride.id, decision == .skip ? .undecided : .skip) }
                }
                .tint(decision == .skip ? .gray : .orange)
            }
        }
        .contextMenu { DecisionButtons(id: ride.id) }
    }
}

/// Going, Maybe, Skip and Undecided, for menus.
struct DecisionButtons: View {
    @Environment(PhoneModel.self) private var model
    let id: String

    var body: some View {
        ForEach(Format.choices, id: \.0) { d, name, icon in
            Button(name, systemImage: icon) { Task { await model.decide(id, d) } }
                .disabled(model.decision(id) == d)
        }
    }
}

enum Format {
    static let choices: [(Decision, String, String)] = [
        (.attending, "Going", "checkmark.circle"), (.maybe, "Maybe", "questionmark.circle"),
        (.skip, "Skip", "xmark.circle"), (.undecided, "Undecided", "circle"),
    ]

    private static func fmt(_ pattern: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_AU")
        f.dateFormat = pattern
        f.amSymbol = "am"
        f.pmSymbol = "pm"
        return f
    }
    static let day = fmt("EEEE d MMMM"), time = fmt("h:mm a")

    static func when(_ ride: RideEvent) -> String {
        ride.allDay ? "\(day.string(from: ride.start)), all day" : "\(day.string(from: ride.start)), \(time.string(from: ride.start))"
    }

    static func place(_ ride: RideEvent) -> String? {
        let km = ride.distanceKm.map { "\(Int($0.rounded())) km away" }
        let parts = [ride.location.isEmpty ? nil : ride.location, km].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
