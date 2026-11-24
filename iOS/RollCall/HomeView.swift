import SwiftUI

/// The first tab: your next ride, the next two weeks, rides waiting for an answer and the others you're going to.
struct HomeView: View {
    @Environment(PhoneModel.self) private var model
    @Environment(\.horizontalSizeClass) private var width
    @AppStorage("ridesLayout") private var layout = RidesLayout.list
    @State private var selected: String?
    @State private var pulledDown = false

    var body: some View {
        let undecided = rides("Undecided"), going = rides("Going")
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Two columns when there's room and something for the second.
                    if width == .regular, !undecided.isEmpty || going.count > 1 {
                        HStack(alignment: .top, spacing: 16) {
                            VStack(spacing: 16) { nextRide(going.first); twoWeeks }
                            VStack(spacing: 16) { toDecide(undecided); alsoGoing(going) }
                        }
                    } else {
                        nextRide(going.first)
                        twoWeeks
                        toDecide(undecided)
                        alsoGoing(going)
                    }
                    status
                }
                .frame(maxWidth: 960)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .animation(.default, value: undecided.map(\.id) + going.map(\.id))
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(width == .regular ? .inline : .automatic)
            .pullToRefresh(progress: model.refreshProgress, refreshing: $pulledDown) {
                await model.refresh()
            }
            .toolbar {
                if model.refreshing, !pulledDown { ToolbarItem { ProgressView() } }
            }
            .navigationDestination(item: $selected) { id in
                RidePage(id: id) { selected = nil }
                    .navigationTitle(model.state.events[id]?.title ?? "").navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private func rides(_ section: String) -> [RideEvent] { model.sections.first { $0.name == section }?.rides ?? [] }

    // MARK: - Cards

    private func nextRide(_ ride: RideEvent?) -> some View {
        HomeCard(title: "Next ride", note: ride.map { Format.until($0) }) {
            if let ride {
                HomeRide(ride: ride, scale: 1.4) { selected = ride.id }
                if ride.hasRoute { RouteButton(ride: ride).padding(.leading, 73) }
            } else {
                Text("You're not going to any rides yet. Mark one Going and it's shown here.").foregroundStyle(.secondary)
            }
        }
    }

    private var twoWeeks: some View {
        let today = Date()
        let weeks = [today, RideCalendar.move(today, by: 1, .week)].flatMap { RideCalendar.grid(of: .week, at: $0) }
        return HomeCard(title: "This week and next", action: "Month", perform: { layout = .month; model.tab = .rides }) {
            RideGrid(weeks: weeks, rides: RideCalendar.byDay(model.calendarRides)) { day in
                model.dayToOpen = day
                model.tab = .rides
            }
        }
    }

    @ViewBuilder private func toDecide(_ rides: [RideEvent]) -> some View {
        if rides.isEmpty, model.state.lastRefresh == nil {
            HomeCard(title: "To decide") {
                Text(model.refreshing ? "Checking sources…" : "No rides yet. Pull down to check your sources, or add more under Sources.")
                    .foregroundStyle(.secondary)
            }
        } else if !rides.isEmpty {
            HomeCard(title: "To decide", count: rides.count, action: "All rides", perform: showList) {
                ForEach(rides.prefix(3), id: \.id) { ride in
                    if ride.id != rides[0].id { Divider() }
                    HomeRide(ride: ride) { selected = ride.id }
                    HStack(spacing: 10) {
                        Button("Going") { Task { await model.decide(ride.id, .attending) } }
                        Button("Skip") { Task { await model.decide(ride.id, .skip) } }
                    }
                    .buttonStyle(.bordered)
                    .padding(.leading, 54)
                }
            }
        }
    }

    @ViewBuilder private func alsoGoing(_ rides: [RideEvent]) -> some View {
        if rides.count > 1 {
            HomeCard(title: "Also going", count: rides.count - 1, action: "All rides", perform: showList) {
                ForEach(rides.dropFirst().prefix(3), id: \.id) { ride in
                    HomeRide(ride: ride) { selected = ride.id }
                }
            }
        }
    }

    /// When the sources were checked, and any that couldn't be.
    private var status: some View {
        let failed = model.state.feeds.filter { $0.type != .chat && model.state.feedErrors[$0.id] != nil }.count
        return VStack(spacing: 8) {
            if failed > 0 {
                Button { model.tab = .sources } label: {
                    ProblemLabel(text: failed == 1 ? "1 source couldn't be read" : "\(failed) sources couldn't be read")
                }
                .buttonStyle(.plain)
            }
            if let checked = model.state.lastRefresh {
                Text("Checked \(checked.formatted(.relative(presentation: .named)))").foregroundStyle(.secondary)
            }
        }
        .font(.footnote)
        .padding(.vertical, 8)
    }

    private func showList() {
        layout = .list
        model.tab = .rides
    }
}

/// A heading and what's under it on a rounded card, with a button or a note beside the heading.
private struct HomeCard<Content: View>: View {
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
                if let note { Text(note).font(.subheadline.weight(.semibold)) }
                if let action { Button(action, action: perform).font(.subheadline) }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
    }
}

/// A ride on Home, which opens its page.
private struct HomeRide: View {
    @Environment(PhoneModel.self) private var model
    let ride: RideEvent
    var scale: CGFloat = 1
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: scale > 1 ? 14 : 12) {
                DateBadge(date: ride.start, decision: model.decision(ride.id), needsCheck: ride.needsCheck == true, scale: scale)
                VStack(alignment: .leading, spacing: 3) {
                    Text(ride.title).font(scale > 1 ? .title3.bold() : .headline).lineLimit(2)
                    Text(Format.when(ride)).font(.subheadline).foregroundStyle(.secondary)
                    if let place = Format.place(ride) {
                        Text(place).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct RouteButton: View {
    @Environment(PhoneModel.self) private var model
    @Environment(\.openURL) private var openURL
    let ride: RideEvent

    var body: some View {
        Button("Route", systemImage: "map") {
            Task { if let url = await model.directions(for: ride) { openURL(url) } }
        }
        .buttonStyle(.bordered)
    }
}
