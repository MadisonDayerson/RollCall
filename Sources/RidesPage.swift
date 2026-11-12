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
                        ForEach(rides, id: \.id) { RideRow(ride: $0, model: model).tag($0.id) }
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

    var body: some View {
        let open = model.rideSectionOpen(section.name)
        VStack(alignment: .leading, spacing: 0) {
            Button { open.wrappedValue.toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: open.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(width: 12)
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
                    let selected = model.selectedRide == r.id
                    RideRow(ride: r, model: model)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6).padding(.horizontal, 8)
                        .background(selected ? Color.primary.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                        .onTapGesture { model.selectedRide = r.id }
                        .padding(.leading, 20)
                    Divider().padding(.leading, 20)
                }
            }
        }
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

    var body: some View {
        let decision = model.store.decision(ride.id)
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
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(decisionName(decision, needsCheck: ride.needsCheck == true)): \(ride.title), \(rideWhen(ride, long: true))")
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
                    Picker("Going?", selection: model.decision(ride.id)) {
                        Text("Going").tag(Decision.attending)
                        Text("Maybe").tag(Decision.maybe)
                        Text("Skip").tag(Decision.skip)
                        Text("Undecided").tag(Decision.undecided)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
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

                // The same buttons for every ride, in the same order; one that can't do anything yet says why.
                Flow {
                    Button("Open event") { app.open(ride.url) }
                        .disabled(ride.url == nil)
                        .help(ride.url == nil ? "This ride has no event page. Add a link with Edit…" : ride.linkHelp)
                    Button("Edit…") { model.later { app.editRide(id: ride.id) } }
                        .help("Change the name, time, place, link or notes. Changes go to the calendar too.")
                    Button("Route") { app.openRoute(ride) }
                        .disabled(!ride.hasRoute)
                        .help(!ride.hasRoute ? "Add a place with Edit… to get a route"
                              : Route.link(in: ride.notes) != nil ? "Open the organiser's route"
                              : "Directions from your suburb to the meeting place and any stops (choose your maps app in Settings)")
                    Button("Remove", role: .destructive) {
                        model.selectedRide = nil
                        if model.isPast(ride) { model.later { app.forgetPastRide(ride.id) } } else { app.removeRide(id: ride.id) }
                    }
                    .help(model.isPast(ride) ? "Remove it from your past rides" : "Remove this ride. It won't come back when its source is checked again.")
                }

                RouteBox(ride: ride, model: model).id(ride.id)

            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
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
