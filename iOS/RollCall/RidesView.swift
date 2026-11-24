import SwiftUI

/// Upcoming rides in Undecided, Going, Skipped and Past. With room (most iPad windows) a ride's page is beside the
/// list, under one title bar: a split view has its own bars, which ended up under the floating tabs when an iPad
/// window changed shape. Otherwise the page opens over the list.
struct RidesView: View {
    @Environment(PhoneModel.self) private var model
    @Environment(\.horizontalSizeClass) private var width
    @State private var selected: String?

    var body: some View {
        NavigationStack {
            if width == .regular {
                HStack(spacing: 0) {
                    list.frame(width: 320)
                    Divider()
                    page(selected).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(Color(.systemGroupedBackground))
                .navigationBarTitleDisplayMode(.inline)
                // Two lists scroll under the bar, so it's kept solid: otherwise what's scrolled shows around the tabs.
                .toolbarBackground(Color(.systemGroupedBackground), for: .navigationBar)
                .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            } else {
                list.navigationDestination(item: $selected) { id in
                    page(id).navigationTitle(model.state.events[id]?.title ?? "").navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        .onChange(of: model.rideToOpen, initial: true) { _, id in
            guard let id else { return }
            selected = id
            model.rideToOpen = nil
        }
    }

    private var list: some View {
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
    }

    @ViewBuilder private func page(_ id: String?) -> some View {
        if let id, let ride = model.state.events[id] {
            RideDetail(ride: ride) { selected = nil }.id(id)
        } else {
            EmptyState(text: "Choose a ride to see its details.")
        }
    }

    private var empty: some View {
        EmptyState(text: model.refreshing ? "Checking sources…" : "No rides yet. Pull down to check your sources, or add more under Sources.")
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
                .tint(decision == .attending ? .gray : .accentColor)
            }
        }
        .swipeActions(edge: .trailing) {
            if !past {
                Button(decision == .skip ? "Undecided" : "Skip", systemImage: decision == .skip ? "arrow.uturn.backward" : "xmark") {
                    Task { await model.decide(ride.id, decision == .skip ? .undecided : .skip) }
                }
                .tint(.gray)
            }
        }
        .contextMenu { DecisionButtons(id: ride.id) }
    }
}

/// Going, Maybe, Skip and Undecided, for menus.
struct DecisionButtons: View {
    @Environment(PhoneModel.self) private var model
    let id: String

    static let choices: [(Decision, String, String)] = [
        (.attending, "Going", "checkmark.circle"), (.maybe, "Maybe", "questionmark.circle"),
        (.skip, "Skip", "xmark.circle"), (.undecided, "Undecided", "circle"),
    ]

    var body: some View {
        ForEach(Self.choices, id: \.0) { d, name, icon in
            Button(name, systemImage: icon) { Task { await model.decide(id, d) } }
                .disabled(model.decision(id) == d)
        }
    }
}
