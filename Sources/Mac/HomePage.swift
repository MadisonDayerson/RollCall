import SwiftUI
import AppKit

/// The first page: your next ride, the next two weeks, rides waiting for an answer and the others you're going to,
/// as on the iPhone and iPad.
struct HomePage: View {
    @ObservedObject var model: UIModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let sections = model.store.groupedRides()
        let undecided = sections.rides(.undecided), going = sections.rides(.going)
        GeometryReader { g in
            ScrollView {
                VStack(spacing: 16) {
                    // Two columns when there's room and something for the second.
                    if g.size.width >= 720, !undecided.isEmpty || going.count > 1 {
                        HStack(alignment: .top, spacing: 16) {
                            VStack(spacing: 16) { nextRide(going.first); twoWeeks }
                            VStack(spacing: 16) { undecidedRides(undecided); alsoGoing(going) }
                        }
                    } else {
                        nextRide(going.first)
                        twoWeeks
                        undecidedRides(undecided)
                        alsoGoing(going)
                    }
                    status
                }
                .frame(maxWidth: 960)
                .padding(20)
                .frame(maxWidth: .infinity)
                .animation(reduceMotion ? nil : .default, value: undecided.map(\.id) + going.map(\.id))
            }
        }
        .glassBackdrop()
        .navigationTitle("Home")
    }

    // MARK: - Cards

    private func nextRide(_ ride: RideEvent?) -> some View {
        HomeCard(title: "Next ride", note: ride.map { Format.until($0) }) {
            if let ride {
                open(ride, large: true)
                if ride.hasRoute {
                    Button { model.app.openRoute(ride) } label: { Label("Route", systemImage: "map") }
                        .buttonStyle(.bordered).controlSize(.large)
                        .padding(.leading, 73)
                }
            } else {
                Text("You're not going to any rides yet. Mark one Going and it's shown here.").foregroundStyle(.secondary)
            }
        }
    }

    private var twoWeeks: some View {
        let today = Date()
        let weeks = [today, RideCalendar.move(today, by: 1, .week)].flatMap { RideCalendar.grid(of: .week, at: $0) }
        return HomeCard(title: "This week and next", action: "Month", perform: {
            model.ridesLayout = .month
            model.calendarDay = Date()
            model.oneDay = false
            model.page = .rides
        }) {
            RideGrid(weeks: weeks, rides: RideCalendar.byDay(model.store.calendarRides()), decision: model.store.decision) { day in
                model.show(day: day)
            }
        }
    }

    @ViewBuilder private func undecidedRides(_ rides: [RideEvent]) -> some View {
        if rides.isEmpty, model.store.state.lastRefresh == nil {
            HomeCard(title: "Undecided") {
                Text(model.app.refreshing ? "Checking sources…" : "No rides yet. RollCall checks your sources by itself; add more with +.")
                    .foregroundStyle(.secondary)
            }
        } else if !rides.isEmpty {
            HomeCard(title: "Undecided", count: rides.count, action: "All rides", perform: showList) {
                ForEach(rides.prefix(3), id: \.id) { ride in
                    if ride.id != rides[0].id { Divider() }
                    open(ride)
                    HStack(spacing: 10) {
                        Button("Going") { model.app.decide(ride.id, .attending) }
                            .accessibilityLabel("Going: \(ride.title)")
                            .buttonStyle(.borderedProminent).brandFill()
                        Button("Skip") { model.app.decide(ride.id, .skip) }
                            .accessibilityLabel("Skip: \(ride.title)")
                            .buttonStyle(.bordered)
                    }
                    .controlSize(.large)
                    .padding(.leading, 54)
                }
            }
        }
    }

    @ViewBuilder private func alsoGoing(_ rides: [RideEvent]) -> some View {
        if rides.count > 1 {
            HomeCard(title: "Also going", count: rides.count - 1, action: "All rides", perform: showList) {
                ForEach(rides.dropFirst().prefix(3), id: \.id) { ride in
                    open(ride)
                }
            }
        }
    }

    /// When the sources were checked, and any that couldn't be.
    private var status: some View {
        let state = model.store.state
        let failed = state.feeds.filter { $0.type != .chat && state.feedErrors[$0.id] != nil }.count
        return VStack(spacing: 8) {
            if failed > 0 {
                Button { model.page = .sources } label: {
                    Label(failed == 1 ? "1 source couldn't be read" : "\(failed) sources couldn't be read",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            }
            if let checked = state.lastRefresh {
                Text("Checked \(AppDelegate.relative.localizedString(for: min(checked, Date().addingTimeInterval(-1)), relativeTo: Date()))")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(.vertical, 8)
    }

    /// A ride, which opens on the Rides page.
    private func open(_ ride: RideEvent, large: Bool = false) -> some View {
        HomeRide(ride: ride, large: large, decision: model.store.decision(ride.id)) { model.reveal(ride: ride.id) }
    }

    private func showList() {
        model.ridesLayout = .list
        model.page = .rides
    }
}

/// A heading and what's under it on a rounded card, with a button or a note beside the heading.
struct HomeCard<Content: View>: View {
    let title: String
    var count: Int? = nil
    var note: String? = nil
    var action: String? = nil
    var perform: () -> Void = {}
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                PatchLabel(text: title, count: count)
                Spacer()
                if let note { Text(note).font(.callout.weight(.semibold)) }
                if let action { Button(action, action: perform).buttonStyle(.link) }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard()
    }
}

/// A ride in short on Home: its date patch, name, day, time and place. Larger for your next ride. It lights up
/// under the pointer, like a list row.
struct HomeRide: View {
    let ride: RideEvent
    let large: Bool
    let decision: Decision
    let open: () -> Void
    @StateObject private var hovering = Box(false)

    var body: some View {
        Button(action: open) {
            HStack(spacing: large ? 14 : 12) {
                DateBadge(date: ride.start, decision: decision, needsCheck: ride.needsCheck == true, scale: large ? 1.4 : 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(ride.title).font(large ? .title3.bold() : .headline).lineLimit(2)
                    Text(Format.when(ride)).foregroundStyle(.secondary)
                    if let place = Format.place(ride) { Text(place).foregroundStyle(.secondary).lineLimit(1) }
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(6)
            .background(Color.primary.opacity(hovering.value ? 0.05 : 0), in: Brand.note)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(-6)
        .onHover { inside in withAnimation(.easeOut(duration: 0.12)) { hovering.value = inside } }
        .accessibilityElement(children: .combine)
        .accessibilityValue(decision.spoken(needsCheck: ride.needsCheck == true))
        .help("Show on the Rides page")
    }
}
