import SwiftUI

/// The rides as a list, or the week's or month's in a calendar. With room (most iPad windows) a ride's page is beside the
/// list, under one title bar: a split view has its own bars, which ended up under the floating tabs when an iPad
/// window changed shape. Otherwise the page opens over the list.
struct RidesView: View {
    @Environment(PhoneModel.self) private var model
    @Environment(\.horizontalSizeClass) private var width
    @AppStorage("ridesLayout") private var layout = RidesLayout.list
    @State private var selected: String?
    /// The day the calendar is at, and whether only that day's rides are listed.
    @State private var day = Date()
    @State private var oneDay = false
    /// The list is held down to refresh, where the logo shows how far it's got.
    @State private var pulledDown = false

    var body: some View {
        NavigationStack {
            if width == .regular {
                HStack(spacing: 0) {
                    list.frame(width: 320)
                    Divider()
                    RidePage(id: selected) { selected = nil }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(Color(.systemGroupedBackground))
                .navigationBarTitleDisplayMode(.inline)
                // A hard edge would be over only the half that scrolls.
                .scrollEdgeEffectStyle(.soft, for: .top)
            } else {
                list.navigationDestination(item: $selected) { id in
                    RidePage(id: id) { selected = nil }.navigationTitle(model.state.events[id]?.title ?? "").navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        .onChange(of: model.rideToOpen, initial: true) { _, id in
            guard let id else { return }
            selected = id
            model.rideToOpen = nil
        }
        .onChange(of: model.dayToOpen, initial: true) { _, new in
            guard let new else { return }
            day = new
            oneDay = true
            if layout == .list { layout = .week }
            // The day's first ride, so its details open, as on the Mac.
            selected = RideCalendar.byDay(model.calendarRides)[Calendar.current.startOfDay(for: new)]?.first?.id
            model.dayToOpen = nil
        }
    }

    private var list: some View {
        List(selection: $selected) {
            switch layout {
            case .list:
                ForEach(model.sections) { if !$0.rides.isEmpty { RideSection(section: $0) } }
            case .week, .month:
                RideCalendarSections(span: layout == .week ? .week : .month, day: $day, oneDay: $oneDay)
            }
        }
        .listSectionSpacing(.compact)
        .navigationTitle("Rides")
        .pullToRefresh(progress: model.refreshProgress, refreshing: $pulledDown) {
            await model.refresh()
            // Takes a while, so the list doesn't stay pulled down for it: each ride shows a spinner while it's looked up.
            Task { await model.findMoreDetails() }
        }
        .overlay { if layout == .list, model.sections.allSatisfy(\.rides.isEmpty) { empty } }
        .toolbar {
            if model.refreshing, !pulledDown { ToolbarItem { ProgressView() }.sharedBackgroundVisibility(.hidden) }
            ToolbarItem {
                Menu {
                    Picker("Show", selection: $layout) {
                        ForEach(RidesLayout.allCases, id: \.self) { Label($0.name, systemImage: $0.icon).tag($0) }
                    }
                } label: {
                    Label("Show", systemImage: layout.icon)
                }
                .accessibilityValue(layout.name)
            }
        }
    }

    private var empty: some View {
        EmptyState(text: model.refreshing ? "Checking sources…" : "No rides yet. Pull down to check your sources, or add more under Sources.")
    }
}

/// One ride in the list. Swipe for Going or Skip.
struct RideRow: View {
    @Environment(PhoneModel.self) private var model
    let ride: RideEvent
    var past = false

    var body: some View {
        let decision = model.decision(ride.id)
        HStack(spacing: 12) {
            RideSummary(ride: ride, past: past)
            // Refresh is looking for more details about this ride.
            if case .looking? = model.lookups[ride.id] {
                Spacer(minLength: 0)
                ProgressView().accessibilityLabel("Looking for more details").transition(.opacity)
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
        .contextMenu { if !past { DecisionButtons(id: ride.id) } }
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
