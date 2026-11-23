import SwiftUI
import AppKit

// MARK: - Rides

struct RidesPage: View {
    @ObservedObject var model: UIModel
    @StateObject private var width = Box(CGFloat(0))  // starts as the menu, which never widens the window

    var body: some View {
        let rides = model.rides()
        ListAndDetail(showingDetail: model.selectedRide != nil, back: "Rides", close: { model.selectedRide = nil }) {
            VStack(spacing: 0) {
                // Tabs when there's room; a menu when the list is narrow (beside a ride's details). Measured
                // rather than left to the tabs, whose full width would otherwise push the window wider.
                Group {
                    if width.value >= 440 {
                        Picker("Show", selection: $model.rideFilter) {
                            ForEach(UIModel.RideFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    } else {
                        Picker("Show", selection: $model.rideFilter) {
                            ForEach(UIModel.RideFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .fixedSize()
                    }
                }
                .labelsHidden()
                // The menu sits at the left, in line with the section headings; the tabs stay centred.
                .frame(maxWidth: .infinity, alignment: width.value >= 440 ? .center : .leading)
                .padding(10)
                .background(GeometryReader { g in
                    Color.clear
                        .onAppear { width.value = g.size.width }
                        .onChange(of: g.size.width) { _, w in width.value = w }
                })
                if rides.isEmpty {
                    EmptyState(text: model.app.refreshing && model.rideFilter != .past ? "Checking sources…" : model.rideFilter.emptyText)
                } else if model.rideFilter == .all {
                    // Drawn by hand rather than as an outline list: macOS's outline list left stray, wrongly placed
                    // section headings behind when sections opened and closed.
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(model.rideSections()) { s in
                                RideSectionView(section: s, model: model)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                    }
                } else {
                    List(selection: $model.selectedRide) {
                        ForEach(rides, id: \.id) { ListRideRow(ride: $0, model: model).tag($0.id) }
                    }
                }
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
}

/// One section of the All tab: a heading that opens and closes, and its rides.
struct RideSectionView: View {
    let section: UIModel.RideSection
    @ObservedObject var model: UIModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let open = model.rideSectionOpen(section.name)
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { open.wrappedValue.toggle() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(width: 12)
                        .rotationEffect(.degrees(open.wrappedValue ? 90 : 0))
                    PatchLabel(text: section.name, count: section.rides.count)
                    Spacer()
                }
                .padding(.top, 14).padding(.bottom, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Divider()
            if open.wrappedValue {
                if section.rides.isEmpty {
                    Text(section.name == "Past" ? "Rides you went on show here once they're over, for as long as Settings → Privacy keeps them." : "None right now.")
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

/// A ride in a list: its ⋯ button shows under the pointer or when it's chosen.
struct ListRideRow: View {
    let ride: RideEvent
    @ObservedObject var model: UIModel
    @StateObject private var hovering = Box(false)

    var body: some View {
        RideRow(ride: ride, model: model, showMenu: model.selectedRide == ride.id || hovering.value)
            .onHover { hovering.value = $0 }
    }
}

/// A ride on the All tab, which is drawn by hand: it lights up under the pointer and when chosen, like a list row.
struct SectionRideRow: View {
    let ride: RideEvent
    @ObservedObject var model: UIModel
    @StateObject private var hovering = Box(false)

    var body: some View {
        let selected = model.selectedRide == ride.id
        RideRow(ride: ride, model: model, showMenu: selected || hovering.value)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6).padding(.horizontal, 8)
            .background(Color.primary.opacity(selected ? 0.1 : hovering.value ? 0.05 : 0), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .onTapGesture { model.selectedRide = ride.id }
            .onHover { inside in withAnimation(.easeOut(duration: 0.12)) { hovering.value = inside } }
            .padding(.leading, 20)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A ride's decision in words, for VoiceOver.
@MainActor func decisionName(_ d: Decision, needsCheck: Bool) -> String {
    switch d {
    case .attending: return "Going"
    case .maybe: return "Maybe"
    case .skip: return "Skipped"
    case .undecided: return needsCheck ? "New, check the date" : "New"
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
            .accessibilityLabel("\(decisionName(decision, needsCheck: ride.needsCheck == true)): \(ride.title), \(rideWhen(ride, long: true))")
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
                    Text(ride.title).font(.title2).fontWeight(.bold).textSelection(.enabled)
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
                        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
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
                Button(maps.name + (maps.holdsStops || Route.places(meetingPlace: ride.location, notes: ride.notes).count < 2 ? "" : " (meeting place only)")) {
                    app.openRoute(ride, in: maps)
                }
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
        let notes = ride.notes
        let full = Web.readableNotes(notes)
        let summarise = !notes.isEmpty && Brief.needsSummary(notes)
        let items = summarise ? Brief.items(in: notes, location: ride.location) : []
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
                            }
                        }
                    }
                    GridRow {
                        Text("From").foregroundStyle(.secondary)
                        // A ride posted in several places shows once; this says where else it was.
                        Text(([ride] + model.store.copies(of: ride)).map(\.sourceName).uniqued().joined(separator: ", "))
                    }
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        GridRow {
                            Text(item.label).foregroundStyle(.secondary)
                            Text(item.value).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if !notes.isEmpty {
                    if !summarise {
                        Text(full).font(.callout).textSelection(.enabled)
                    } else {
                        if items.isEmpty { Text(Brief.opening(notes)).font(.callout).textSelection(.enabled) }
                        Button(more.value ? "See less" : "See more") { more.value.toggle() }
                            .buttonStyle(.link)
                        if more.value {
                            Divider()
                            Text(full).font(.callout).textSelection(.enabled)
                        }
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
    let lookup: UIModel.Lookup
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
