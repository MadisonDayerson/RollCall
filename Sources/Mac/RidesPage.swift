import SwiftUI
import AppKit

// MARK: - Rides

struct RidesPage: View {
    @ObservedObject var model: UIModel

    var body: some View {
        ListAndDetail(showingDetail: model.selectedRide != nil, back: "Rides", close: { model.selectedRide = nil }) {
            Group {
                switch model.ridesLayout {
                case .list: list
                case .week: RideCalendarView(model: model, span: .week)
                case .month: RideCalendarView(model: model, span: .month)
                }
            }
            .floatingBar(.top) {
                Picker("Show", selection: $model.ridesLayout) {
                    ForEach(RidesLayout.allCases, id: \.self) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .frame(maxWidth: .infinity)
                .padding(10)
            }
        } detail: {
            Group {
                if let id = model.selectedRide, let ride = model.store.state.events[id] {
                    RideDetail(ride: ride, model: model)
                } else {
                    EmptyState(text: "Choose a ride to see its details.")
                }
            }
        }
        .navigationTitle("Rides")
    }

    @ViewBuilder private var list: some View {
        let sections = model.store.groupedRides()
        if sections.allSatisfy(\.rides.isEmpty) {
            EmptyState(text: model.app.refreshing ? "Checking sources…" : "No rides yet. RollCall checks your sources by itself; add more with +.")
        } else {
            // Drawn by hand rather than as an outline list: macOS's outline list left stray, wrongly placed
            // section headings behind when sections opened and closed.
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sections) { RideSectionView(section: $0, model: model) }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
    }
}

/// The week or month: the days in a grid, with their rides listed underneath. Choosing a day lists just its rides;
/// choosing it again goes back to all of them.
struct RideCalendarView: View {
    @ObservedObject var model: UIModel
    let span: RideCalendar.Span
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let rides = RideCalendar.byDay(model.store.calendarRides())
        let day = model.calendarDay
        let start = Calendar.current.startOfDay(for: day)
        let shown = (model.oneDay ? [start] : RideCalendar.days(of: span, at: day)).filter { rides[$0] != nil }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    heading
                    RideGrid(weeks: RideCalendar.grid(of: span, at: day), rides: rides, chosen: model.oneDay ? start : nil,
                             decision: model.store.decision) { new in
                        model.oneDay = !(model.oneDay && new == start)
                        model.calendarDay = new
                        // A day with rides shows its first one's details.
                        if model.oneDay, let first = rides[new]?.first { model.selectedRide = first.id }
                    }
                    Text("Filled: going. Dashed: maybe. Outlined: undecided.")
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                }
                .padding(.horizontal, 12).padding(.bottom, 12)
                .glassCard()
                .padding(.top, 8)
                ForEach(shown, id: \.self) { date in
                    PatchLabel(text: Format.day.string(from: date)).padding(.leading, 20).padding(.top, 18).padding(.bottom, 7)
                    Divider()
                    ForEach(rides[date] ?? [], id: \.id) { r in
                        SectionRideRow(ride: r, model: model)
                        Divider().padding(.leading, 20)
                    }
                }
                if shown.isEmpty {
                    Text(model.oneDay ? "No rides on \(Format.day.string(from: day))." : span == .week ? "No rides this week." : "No rides this month.")
                        .foregroundStyle(.secondary).padding(.top, 18)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .glassBackdrop()
    }

    private var heading: some View {
        HStack(spacing: 4) {
            Text(Format.span(span, at: model.calendarDay)).font(.headline)
            Spacer()
            if !RideCalendar.days(of: span, at: model.calendarDay).contains(Calendar.current.startOfDay(for: Date())) {
                Button("Today") { show(Date()) }.padding(.trailing, 8)
            }
            arrow("Previous \(name)", "chevron.left", -1)
            arrow("Next \(name)", "chevron.right", 1)
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 8)
    }

    private func arrow(_ title: String, _ icon: String, _ n: Int) -> some View {
        Button { show(RideCalendar.move(model.calendarDay, by: n, span)) } label: {
            Label(title, systemImage: icon).labelStyle(.iconOnly).frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .help(title)
    }

    private var name: String { span == .week ? "week" : "month" }

    /// Goes to the week or month with the day in it.
    private func show(_ new: Date) {
        withAnimation(reduceMotion ? nil : .default) {
            model.calendarDay = new
            model.oneDay = false
        }
    }
}

/// One section of the list: a heading that opens and closes, and its rides.
struct RideSectionView: View {
    let section: GroupedRides
    @ObservedObject var model: UIModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let open = model.rideSectionOpen(section.group.rawValue)
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { open.wrappedValue.toggle() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(width: 12)
                        .rotationEffect(.degrees(open.wrappedValue ? 90 : 0))
                    PatchLabel(text: section.group.rawValue, count: section.rides.count)
                    Spacer()
                }
                .padding(.top, 14).padding(.bottom, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Divider()
            if open.wrappedValue {
                if section.rides.isEmpty {
                    Text(section.group == .past ? "Rides you went on show here once they're over, for as long as Settings → Privacy keeps them." : "None right now.")
                        .font(.callout).foregroundStyle(.secondary)
                        .padding(.leading, 28).padding(.vertical, 8)
                }
                ForEach(section.rides, id: \.id) { r in
                    SectionRideRow(ride: r, model: model)
                    Divider().padding(.leading, 20)
                }
            }
        }
        .clipped()
    }
}

/// A ride in the list or under a day, which is drawn by hand: it lights up under the pointer and when chosen, like a list row.
struct SectionRideRow: View {
    let ride: RideEvent
    @ObservedObject var model: UIModel
    @StateObject private var hovering = Box(false)

    var body: some View {
        let selected = model.selectedRide == ride.id
        RideRow(ride: ride, model: model, showMenu: selected || hovering.value)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6).padding(.horizontal, 8)
            .background(Color.primary.opacity(selected ? 0.1 : hovering.value ? 0.05 : 0), in: Brand.note)
            .contentShape(Rectangle())
            .onTapGesture { model.selectedRide = ride.id }
            .onHover { inside in withAnimation(.easeOut(duration: 0.12)) { hovering.value = inside } }
            .padding(.leading, 20)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

@MainActor func rideWhen(_ r: RideEvent, long: Bool = false) -> String {
    if long {
        var s = r.allDay ? AppDelegate.longDayFmt.string(from: r.start) : AppDelegate.longFmt.string(from: r.start)
        if let end = r.end, !r.allDay { s += " – " + AppDelegate.timeFmt.string(from: end) }
        return s
    }
    return r.allDay ? AppDelegate.dayFmt.string(from: r.start) : AppDelegate.dayTimeFmt.string(from: r.start)
}

struct RideRow: View {
    let ride: RideEvent
    @ObservedObject var model: UIModel
    /// The ⋯ button shows under the pointer or when the ride is chosen, so the list stays calm.
    let showMenu: Bool

    var body: some View {
        let decision = model.store.decision(ride.id)
        HStack(alignment: .top, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                DateBadge(date: ride.start, decision: decision, needsCheck: ride.needsCheck == true, past: model.isPast(ride))
                VStack(alignment: .leading, spacing: 2) {
                    Text(ride.title).fontWeight(.semibold).lineLimit(2)
                    Text(ride.allDay ? "All day" : AppDelegate.timeFmt.string(from: ride.start)).font(.callout)
                    Text([ride.location.isEmpty ? nil : ride.location,
                          ride.distanceKm.map { String(format: "%.0f km", $0) },
                          ride.sourceName].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(decision.spoken(needsCheck: ride.needsCheck == true)): \(ride.title), \(rideWhen(ride, long: true))")
            // Refresh is looking for more details about this ride.
            if case .looking(let step)? = model.lookups[ride.id] {
                ProgressView().controlSize(.small).padding(.top, 2)
                    .help(step)
                    .accessibilityLabel("Looking for more details")
                    .transition(.opacity)
            }
            RideActions(ride: ride, model: model)
                .opacity(showMenu ? 1 : 0)
        }
        .padding(.vertical, 3)
        .contextMenu { RideActionItems(ride: ride, model: model) }
    }
}

struct RideDetail: View {
    let ride: RideEvent
    @ObservedObject var model: UIModel

    var body: some View {
        let app = model.app
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 16) {
                    DateBadge(date: ride.start, decision: model.store.decision(ride.id), needsCheck: ride.needsCheck == true,
                              past: model.isPast(ride), scale: 1.5)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ride.title).font(.title2).fontWeight(.bold).textSelection(.enabled)
                        Text(model.store.sourceLine(ride))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                if model.isPast(ride) {
                    Label("You went", systemImage: "checkmark.seal")
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.14), in: Capsule())
                } else {
                    DecisionPicker(decision: model.store.decision(ride.id)) { d in model.later { app.decide(ride.id, d) } }
                    Text("Going adds it to the RollCall calendar, with a reminder the evening before.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if ride.needsCheck == true {
                    Label("The date and place were read from a post or message. Check them before going.",
                          systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.15), in: Brand.note)
                }
                RideAbout(ride: ride, model: model).id(ride.id)

                if let lookup = model.lookups[ride.id] { RideFindings(id: ride.id, lookup: lookup, forPlan: false, model: model) }

                RouteBox(ride: ride, model: model).id(ride.id)

            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A ride's actions, in the ⋯ button on its row and when you right-click it.
struct RideActions: View {
    let ride: RideEvent
    @ObservedObject var model: UIModel

    var body: some View {
        Menu { RideActionItems(ride: ride, model: model) } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(Color.primary.opacity(0.07), in: Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Open, route, edit or remove")
        .accessibilityLabel("Actions for \(ride.title)")
    }
}

/// Going there first, then changing the ride, then removing it. Every ride has the same items in the same order;
/// one that can't do anything yet is greyed out and says why.
struct RideActionItems: View {
    let ride: RideEvent
    @ObservedObject var model: UIModel

    var body: some View {
        let app = model.app
        let past = model.isPast(ride)
        Button(ride.openLabel) { app.open(ride.url) }
            .disabled(ride.url == nil)
        Menu(ride.hasRoute ? "Open route in" : "Open route in (no place)") {
            if Route.link(in: ride.notes) != nil {
                Button("Organiser's route") { app.openRoute(ride) }
                Divider()
            }
            ForEach(MapsApp.allCases.filter { $0 != .automatic && ($0 != .apple || app.hasAppleMaps) }, id: \.self) { maps in
                Button(maps.title(for: ride)) { app.openRoute(ride, in: maps) }
            }
        }
        .disabled(!ride.hasRoute)
        Divider()
        Button("Edit…") { model.later { app.editRide(id: ride.id) } }
        Divider()
        Button(past ? "Remove from past rides" : "Remove", role: .destructive) {
            if model.selectedRide == ride.id { model.selectedRide = nil }
            if past { model.later { app.forgetPastRide(ride.id) } } else { app.removeRide(id: ride.id) }
        }
    }
}

/// When, where and who it's from, then the description: the few lines that matter in plain words,
/// with the whole thing under See more.
struct RideAbout: View {
    let ride: RideEvent
    @ObservedObject var model: UIModel
    @StateObject private var more = Box(false)

    var body: some View {
        let about = Brief.summary(of: ride.notes, location: ride.location)
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow { Text("When").foregroundStyle(.secondary); Text(rideWhen(ride, long: true)) }
                    if !ride.location.isEmpty {
                        GridRow {
                            Text("Where").foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ride.location).textSelection(.enabled)
                                if let km = ride.distanceKm {
                                    Text(String(format: "%.0f km from %@", km, model.store.state.settings.homeName))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                if let note = model.store.meetingNote(ride) {
                                    Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    ForEach(Array(about.items.enumerated()), id: \.offset) { _, item in
                        GridRow {
                            Text(item.label).foregroundStyle(.secondary)
                            Text(item.value).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if let text = about.text { Text(text).font(.callout).textSelection(.enabled) }
                if let full = about.more {
                    Button(more.value ? "See less" : "See more") { more.value.toggle() }
                        .buttonStyle(.link)
                    if more.value {
                        Divider()
                        Text(full).font(.callout).textSelection(.enabled)
                    }
                }
            }
            // Room between the text and the box's edge.
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("About", systemImage: "text.alignleft")
        }
    }
}

/// What Refresh found about a ride or plan: each detail with where it came from. A ride's are added one at a time; a plan's
/// fill in its Add ride form, apart from any you leave out.
struct RideFindings: View {
    let id: String
    let lookup: RideSearch.Lookup
    let forPlan: Bool
    @ObservedObject var model: UIModel

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                switch lookup {
                case .looking(let step):
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text(step).foregroundStyle(.secondary) }
                case .done(let found, let checked):
                    if !found.isEmpty {
                        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                            ForEach(found) { f in
                                GridRow {
                                    Text(f.label).foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(f.value).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                        Text("From \(f.from)").font(.caption).foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    if forPlan {
                                        Button("Leave out") { model.app.leaveOut(f, from: id) }
                                            .help("Don't fill this in when you add the ride")
                                    } else {
                                        Button("Add") { model.app.useFinding(f, rideID: id) }
                                            .help("Add it to the ride, as if you'd typed it with Edit…")
                                    }
                                }
                            }
                        }
                        Text("Apple Intelligence checked each of these is about this \(forPlan ? "plan" : "ride").\(forPlan ? " They're filled in when you add the ride." : "") Looked through \(checked).")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Button(forPlan ? "Clear" : "Done") { model.lookups[id] = nil }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("More details", systemImage: "magnifyingglass")
        }
    }
}
