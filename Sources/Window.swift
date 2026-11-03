import SwiftUI
import AppKit

/// What the window shows, kept in step with the saved state.
@MainActor
final class UIModel: ObservableObject {
    enum Page: String, Hashable, CaseIterable {
        case rides, review, sources, settings
    }
    enum RideFilter: String, CaseIterable {
        case all = "All", undecided = "Undecided", going = "Going", skipped = "Skipped", past = "Past"

        /// What an empty tab says: what belongs here and how rides get here.
        var emptyText: String {
            switch self {
            case .all: return "No rides yet. RollCall checks your sources by itself; add more with +."
            case .undecided: return "Nothing to decide on. New rides from your sources show up here."
            case .going: return "Rides you mark Going show here, and go in your RollCall calendar."
            case .skipped: return "Rides you skip show here, in case you change your mind."
            case .past: return "Rides you mark Going move here once they're over, so you can still share footage and find everyone's posts."
            }
        }
    }

    unowned let app: AppDelegate
    @Published var page: Page = .rides
    @Published var showAdd = false
    @Published var selectedSource: String?
    @Published var selectedRide: String?
    @Published var selectedReview: String?
    @Published var rideFilter: RideFilter = .all
    private var observer: NSObjectProtocol?

    init(app: AppDelegate) {
        self.app = app
        observer = NotificationCenter.default.addObserver(forName: Store.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.objectWillChange.send() }
        }
    }

    var store: Store { app.store }

    /// Runs an action after the current click finishes, so sheets can close before a dialog opens.
    func later(_ action: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async { MainActor.assumeIsolated { action() } }
    }

    // MARK: Rides

    func rides() -> [RideEvent] {
        if rideFilter == .past { return store.past() }
        let all = store.upcoming()
        switch rideFilter {
        case .past: return []
        // Same as the All tab's Undecided section: not decided yet, or maybe.
        case .undecided: return all.filter { [.undecided, .maybe].contains(store.decision($0.id)) }
        case .all: return rideSections().flatMap(\.rides)
        case .going: return all.filter { store.decision($0.id) == .attending }
        case .skipped: return all.filter { store.decision($0.id) == .skip }
        }
    }

    /// The All tab: every ride once, in folding sections.
    struct RideSection: Identifiable {
        var id: String { name }
        var name: String
        var rides: [RideEvent]
    }

    func rideSections() -> [RideSection] {
        let all = store.upcoming()
        return [
            RideSection(name: "Undecided", rides: all.filter { [.undecided, .maybe].contains(store.decision($0.id)) }),
            RideSection(name: "Going", rides: all.filter { store.decision($0.id) == .attending }),
            RideSection(name: "Skipped", rides: all.filter { store.decision($0.id) == .skip }),
            RideSection(name: "Past", rides: store.past()),
        ]
    }

    func section(of id: String) -> String? { rideSections().first { $0.rides.contains { $0.id == id } }?.name }

    /// Skipped and Past start folded away; whatever the person opens or closes is remembered.
    @Published var closedRideSections = Set((UserDefaults.standard.stringArray(forKey: "closedRideSections") ?? ["Skipped", "Past"])
        .map { $0 == "Upcoming" ? "Undecided" : $0 }) {  // "Upcoming" was the section's old name
        didSet { UserDefaults.standard.set(Array(closedRideSections).sorted(), forKey: "closedRideSections") }
    }

    func rideSectionOpen(_ name: String) -> Binding<Bool> {
        Binding(get: { !self.closedRideSections.contains(name) },
                set: { open in if open { self.closedRideSections.remove(name) } else { self.closedRideSections.insert(name) } })
    }

    /// Shows a ride on the Rides page, opening its section on the All tab.
    func reveal(ride id: String) {
        if rideFilter != .all { rideFilter = .all }
        if let s = section(of: id) { closedRideSections.remove(s) }
        selectedRide = id
        page = .rides
    }

    func isPast(_ ride: RideEvent) -> Bool { (ride.end ?? ride.start.addingTimeInterval(3 * 3600)) < Date() }

    var undecidedCount: Int { store.upcoming().filter { store.decision($0.id) == .undecided }.count }

    func decision(_ id: String) -> Binding<Decision> {
        Binding(get: { self.store.decision(id) }, set: { d in self.later { self.app.decide(id, d) } })
    }

    // MARK: Sources

    struct SourceRow: Identifiable, Hashable {
        enum Kind: Hashable { case feed(FeedKind), instagram, facebook, yours }
        var id: String
        var kind: Kind
        var name: String
        var kindName: String
        var symbol: String
        var automatic: Bool
        var problem: String?
        var rides: Int
        var status: String
        /// The app or site it's grouped under, and minutes between automatic checks (feeds only).
        var group: String
        var interval: Int? = nil
    }

    struct SourceGroup: Identifiable {
        var id: String { name }
        var name: String
        var symbol: String
        var rows: [SourceRow]
    }

    /// Sources grouped by app: chat apps, then websites and calendars, then the ones you check yourself.
    func sourceGroups() -> [SourceGroup] {
        let rows = sourceRows()
        func rank(_ r: SourceRow) -> Int {
            if case .feed(let k) = r.kind { return k == .chat ? 0 : 1 }
            return r.kind == .yours ? 3 : 2
        }
        var order: [String] = []
        for r in rows.sorted(by: { (rank($0), $0.group.lowercased()) < (rank($1), $1.group.lowercased()) })
            where !order.contains(r.group) { order.append(r.group) }
        return order.map { g in
            let members = rows.filter { $0.group == g }
            return SourceGroup(name: g, symbol: members[0].symbol, rows: members)
        }
    }

    @Published var collapsedGroups = Set(UserDefaults.standard.stringArray(forKey: "collapsedSourceGroups") ?? []) {
        didSet { UserDefaults.standard.set(Array(collapsedGroups).sorted(), forKey: "collapsedSourceGroups") }
    }

    func expanded(_ group: String) -> Binding<Bool> {
        Binding(get: { !self.collapsedGroups.contains(group) },
                set: { open in if open { self.collapsedGroups.remove(group) } else { self.collapsedGroups.insert(group) } })
    }

    /// Changes how often a source is checked; the default for its kind is stored as nil.
    func setInterval(_ minutes: Int, for ids: [String]) {
        for id in ids {
            setFeed(id) { $0.every = minutes == Feed.defaultInterval($0.type) ? nil : minutes }
        }
        objectWillChange.send()
    }

    static let yourSources: Set<String> = ["manual", "file", "instagram"]

    func rides(fromSource id: String) -> [RideEvent] {
        store.upcoming().filter { id == "yours" ? Self.yourSources.contains($0.source) : $0.source == id }
    }

    func sourceRows() -> [SourceRow] {
        let s = store.state
        var rows: [SourceRow] = s.feeds.map { f in
            let kindName: String, symbol: String
            switch f.type {
            case .calendar: (kindName, symbol) = ("Calendar feed", "calendar")
            case .webpage: (kindName, symbol) = ("Website events", "globe")
            case .posts: (kindName, symbol) = ("News or blog feed", "newspaper")
            case .forum: (kindName, symbol) = ("Forum", "text.bubble")
            case .chat: (kindName, symbol) = ("Beeper chat", "bubble.left.and.bubble.right")
            }
            var status = "Not checked yet"
            if app.checking.contains(f.id) || (app.refreshing && s.lastChecked[f.id] == nil) {
                status = "Checking…"
            } else if let d = s.lastChecked[f.id] {
                // A check that finished this very second would otherwise read "in 0 seconds".
                status = "Checked " + AppDelegate.relative.localizedString(for: min(d, Date().addingTimeInterval(-1)), relativeTo: Date())
            }
            return SourceRow(id: f.id, kind: .feed(f.type), name: f.name, kindName: kindName, symbol: symbol,
                             automatic: f.interval > 0, problem: s.feedErrors[f.id], rides: rides(fromSource: f.id).count, status: status,
                             group: f.app, interval: f.interval)
        }
        rows += s.instagram.map { a in
            SourceRow(id: "instagram:" + a.handle, kind: .instagram, name: "@" + a.handle, kindName: "Instagram account",
                      symbol: "camera", automatic: false, problem: nil, rides: 0,
                      status: a.lastOpened.map { "Looked " + AppDelegate.relative.localizedString(for: $0, relativeTo: Date()) } ?? "Not looked at yet",
                      group: "Instagram")
        }
        rows.append(SourceRow(id: "facebook", kind: .facebook, name: "Facebook events", kindName: "Events you add",
                              symbol: "person.3", automatic: false, problem: nil, rides: rides(fromSource: "facebook").count,
                              status: s.settings.watchDownloads ? "Picks up event downloads" : "Add events by hand", group: "Facebook"))
        rows.append(SourceRow(id: "yours", kind: .yours, name: "Added by you", kindName: "Rides you typed, pasted or imported",
                              symbol: "square.and.pencil", automatic: false, problem: nil, rides: rides(fromSource: "yours").count,
                              status: "Typed in, pasted or imported", group: "Added by you"))
        return rows
    }

    func feed(_ id: String) -> Feed? { store.state.feeds.first { $0.id == id } }

    func setFeed(_ id: String, _ change: (inout Feed) -> Void) {
        guard let i = store.state.feeds.firstIndex(where: { $0.id == id }) else { return }
        change(&store.state.feeds[i])
        store.save()
    }

    func removable(_ id: String?) -> Bool {
        guard let id else { return false }
        return id != "facebook" && id != "yours"
    }
}

/// A value a view can change and watch (stands in for @State, which needs a compiler plugin).
final class Box<T>: ObservableObject {
    @Published var value: T
    init(_ value: T) { self.value = value }
}

// MARK: - Window

struct MainView: View {
    @ObservedObject var model: UIModel

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { model.page }, set: { if let p = $0 { model.page = p } })) {
                // The tag must come last: a badge added after it hides the tag and the row can't be selected.
                Label("Rides", systemImage: "motorcycle")
                    .badge(model.undecidedCount)
                    .tag(UIModel.Page.rides)
                Label("To review", systemImage: "tray")
                    .badge(model.app.openReviews().count + model.app.postsToLookAt().count)
                    .tag(UIModel.Page.review)
                Label("Sources", systemImage: "antenna.radiowaves.left.and.right").tag(UIModel.Page.sources)
                Label("Settings", systemImage: "gearshape").tag(UIModel.Page.settings)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 190)
            .safeAreaInset(edge: .bottom) { Wordmark().padding(.bottom, 14) }
        } detail: {
            switch model.page {
            case .rides: RidesPage(model: model)
            case .review: ReviewPage(model: model)
            case .sources: SourcesPage(model: model)
            case .settings: SettingsPage(model: model)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { Task { await model.app.refresh() } } label: {
                    Label("Check all sources now", systemImage: "arrow.clockwise")
                }
                .help("Check all sources now")
                .disabled(model.app.refreshing)
                Button { model.showAdd = true } label: { Label("Add", systemImage: "plus") }
                    .help("Add a source or a ride")
            }
        }
        .sheet(isPresented: $model.showAdd) { AddSheet(model: model) }
    }
}

/// RollCall's look, taken from its icon: black and white, a thin double frame like a club patch, spaced
/// capitals like the "ROLLCALL" under the logo, and the gothic lettering saved for a few brand moments.
/// Colour is left for meaning (warnings, problems), so the monochrome reads as the brand.
enum Brand {
    /// Gothic lettering drawn by Design/make_wordmark.swift. It's a picture of the letters (the font itself
    /// isn't shipped), drawn black and tinted like the text around it, so it follows light and dark mode.
    static func gothic(_ name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"), let img = NSImage(contentsOf: url) else { return nil }
        img.isTemplate = true
        return img
    }
    static let wordmark = gothic("Wordmark")
    static let monogram = gothic("Monogram")
    /// What the window's text sits on, for lettering cut out of a filled patch.
    static let paper = Color(nsColor: .windowBackgroundColor)
}

/// A heading in spaced capitals, like the "ROLLCALL" under the logo.
struct PatchLabel: View {
    let text: String
    var count: Int? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(text.uppercased()).font(.caption.weight(.heavy)).tracking(1.8)
            if let count { Text("\(count)").font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(.tertiary) }
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

/// A ride's date as a small patch with a single frame: month, day and weekday. Filled (like the icon)
/// for rides you're going to, dashed for maybe, outlined while undecided, faded once skipped or past.
struct DateBadge: View {
    let date: Date
    let decision: Decision
    var needsCheck = false
    var past = false
    var scale: CGFloat = 1

    var body: some View {
        let filled = decision == .attending
        let ink: Color = filled ? Brand.paper : .primary
        let outer = RoundedRectangle(cornerRadius: 9 * scale, style: .continuous)
        VStack(spacing: -1 * scale) {
            Text(Self.month.string(from: date).uppercased())
                .font(.system(size: 7.5 * scale, weight: .heavy)).tracking(1 * scale)
            Text(Self.day.string(from: date))
                .font(.system(size: 19 * scale, weight: .black).width(.condensed)).monospacedDigit()
            Text(Self.weekday.string(from: date).uppercased())
                .font(.system(size: 7.5 * scale, weight: .heavy)).tracking(1 * scale)
        }
        .foregroundStyle(ink)
        .frame(width: 40 * scale, height: 46 * scale)
        .background { if filled { outer.fill(Color.primary) } }
        .overlay {
            outer.strokeBorder(Color.primary, style: StrokeStyle(lineWidth: 1.25 * scale,
                                                                 dash: decision == .maybe ? [3 * scale, 2 * scale] : []))
        }
        .overlay(alignment: .topTrailing) {
            if needsCheck {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 12 * scale, weight: .bold))
                    .background(Circle().fill(Brand.paper))
                    .offset(x: 5 * scale, y: -5 * scale)
            }
        }
        .opacity(decision == .skip ? 0.4 : past ? 0.65 : 1)
        .accessibilityHidden(true)
    }

    private static func fmt(_ f: String) -> DateFormatter {
        let d = DateFormatter(); d.locale = Locale(identifier: "en_AU"); d.dateFormat = f; return d
    }
    static let month = fmt("MMM"), day = fmt("d"), weekday = fmt("EEE")
}

/// An empty page: the gothic "RC" with a line of help underneath.
struct EmptyState: View {
    let text: String
    var detail: String? = nil

    var body: some View {
        VStack(spacing: 14) {
            if let img = Brand.monogram {
                Image(nsImage: img).renderingMode(.template).resizable().scaledToFit()
                    .frame(height: 46).foregroundStyle(.quaternary).accessibilityHidden(true)
            }
            VStack(spacing: 6) {
                Text(text)
                if let detail { Text(detail).font(.callout) }
            }
            .foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// "Roll Call" in the logo's gothic lettering, at the foot of the sidebar.
struct Wordmark: View {
    var body: some View {
        if let img = Brand.wordmark {
            Image(nsImage: img)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 120, maxHeight: 34)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Roll Call")
        }
    }
}

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
                    Text(section.name == "Past" ? "Rides you went on show here once they're over." : "None right now.")
                        .font(.callout).foregroundStyle(.secondary)
                        .padding(.leading, 28).padding(.vertical, 8)
                }
                ForEach(section.rides, id: \.id) { r in
                    let selected = model.selectedRide == r.id
                    RideRow(ride: r, model: model)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6).padding(.horizontal, 8)
                        .background(selected ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                        .onTapGesture { model.selectedRide = r.id }
                        .padding(.leading, 20)
                    Divider().padding(.leading, 28)
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
                if ride.needsCheck == true {
                    Label("The date and place were read from a post or message. Check them before going.",
                          systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.yellow.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
                }
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
                    GridRow { Text("From").foregroundStyle(.secondary); Text(ride.sourceName) }
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

                HStack {
                    if let url = ride.url {
                        // A finished ride has nothing left to RSVP to.
                        Button(model.isPast(ride) && ride.linkLabel == "RSVP" ? "Open event" : ride.linkLabel) { app.open(url) }
                            .help(ride.linkHelp)
                    }
                    if !ride.location.isEmpty {
                        Button("Map") { app.openMaps(place: ride.location) }.help("Show the meeting place in Maps")
                    }
                    if let g = ride.groupURL {
                        Button("Join group") { app.open(g) }.help("Open the group's page to join it")
                    } else if ride.isFacebook {
                        Button("Add group…") { model.later { app.setGroupLink(rideID: ride.id) } }
                    }
                    if !model.isPast(ride), Store.userAdded.contains(ride.source) || ride.needsCheck == true {
                        Button("Remove", role: .destructive) {
                            model.selectedRide = nil
                            app.removeRide(id: ride.id)
                        }
                    }
                    if model.isPast(ride) {
                        Button("Remove") {  // from past rides
                            model.selectedRide = nil
                            model.later { model.app.forgetPastRide(ride.id) }
                        }
                    }
                }

                RideTogether(ride: ride, model: model)

                if !ride.notes.isEmpty {
                    GroupBox {
                        Text(Web.readableNotes(ride.notes))
                            .font(.callout)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - To review

struct ReviewPage: View {
    @ObservedObject var model: UIModel

    var body: some View {
        let plans = model.app.openReviews()
        let posts = model.app.postsToLookAt()
        ScrollViewReader { scroller in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Possible plans").font(.title3).fontWeight(.semibold)
                        Spacer()
                        Text(PlanSummariser.modelAvailable ? "Summaries by Apple Intelligence, on this Mac" : "Summaries are RollCall's best guess")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Conversations in your chats where people mention a time, day or date for a ride. Check what RollCall made of it, then add it as a ride or dismiss it.")
                        .font(.callout).foregroundStyle(.secondary)
                    if plans.isEmpty {
                        Text("Nothing to review.").foregroundStyle(.secondary).padding(.vertical, 8)
                    }
                    ForEach(plans, id: \.id) { r in
                        PlanCard(review: r, model: model).id(r.id)
                    }

                    Divider().padding(.vertical, 6)
                    HStack {
                        Text("Posts without a day").font(.title3).fontWeight(.semibold)
                        Spacer()
                        Button("Mark all as read") { model.app.markPostsRead() }.disabled(posts.isEmpty)
                    }
                    Text("Ride posts and invites that didn't say when. Open one to read it, or turn it into a ride.")
                        .font(.callout).foregroundStyle(.secondary)
                    if posts.isEmpty {
                        Text("Nothing new.").foregroundStyle(.secondary).padding(.vertical, 8)
                    }
                    ForEach(posts, id: \.post.id) { item in
                        PostRow(feed: item.feed, post: item.post, model: model)
                        Divider()
                    }
                }
                .padding(20)
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .onAppear { if let id = model.selectedReview { scroller.scrollTo(id, anchor: .top) } }
            .onChange(of: model.selectedReview) { _, id in if let id { withAnimation { scroller.scrollTo(id, anchor: .top) } } }
        }
        .navigationTitle("To review")
    }
}

struct PlanCard: View {
    let review: PlanReview
    @ObservedObject var model: UIModel

    var body: some View {
        let s = review.summary
        let app = model.app
        let chatName = model.feed(review.feedID)?.name ?? "Chat"
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right").foregroundStyle(.secondary)
                Text(chatName).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                Text("· " + AppDelegate.relative.localizedString(for: min(review.updated, Date().addingTimeInterval(-1)), relativeTo: Date()))
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Label(s.byAI ? "On-device summary" : "Best guess", systemImage: s.byAI ? "sparkles" : "text.magnifyingglass")
                    .font(.caption)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.14), in: Capsule())
            }
            Text(s.title).font(.headline)
            Text(s.summary).textSelection(.enabled)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 5) {
                GridRow { Text("When").foregroundStyle(.secondary); Text(s.when) }
                GridRow { Text("Where").foregroundStyle(.secondary); Text(s.place ?? "Not settled") }
                if !s.who.isEmpty {
                    GridRow { Text("Who's in").foregroundStyle(.secondary); Text(s.who.joined(separator: ", ")) }
                }
                if let u = s.undecided {
                    GridRow { Text("Still open").foregroundStyle(.secondary); Text(u) }
                }
            }
            .font(.callout)

            DisclosureGroup("The conversation (\(review.lines.count) message\(review.lines.count == 1 ? "" : "s"))") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(review.lines, id: \.id) { l in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(AppDelegate.timeFmt.string(from: l.sent)).font(.caption).foregroundStyle(.secondary)
                                .frame(width: 58, alignment: .trailing)
                            Text((l.sender.isEmpty ? "" : l.sender + ": ") + l.text)
                                .font(.callout)
                                .fontWeight(l.mentionsWhen ? .semibold : .regular)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.top, 6)
            }
            .font(.callout)

            HStack {
                Button("Add ride…") { model.later { app.addRide(fromReview: review.id) } }
                    .buttonStyle(.borderedProminent)
                Button("Open chat") { app.open(Beeper.chatLink(chatID: review.chatID, messageID: review.keyMessage?.id)) }
                Spacer()
                Button("Not a ride") { app.dismissReview(review.id) }
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(model.selectedReview == review.id ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct PostRow: View {
    let feed: Feed
    let post: PostItem
    @ObservedObject var model: UIModel

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: feed.type == .chat ? "bubble.left" : "doc.text").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(post.title).fontWeight(.medium).lineLimit(2)
                if !post.text.isEmpty, post.text != post.title {
                    Text(post.text).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                }
                Text(feed.name + (post.published.map { " · " + AppDelegate.relative.localizedString(for: $0, relativeTo: Date()) } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Button("Open") { model.app.open(post.link) }
                Button("Add ride…") {
                    // The post dialog starts with the clipboard, so put the post there.
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(post.text, forType: .string)
                    let link = post.link.hasPrefix("http") ? post.link : ""
                    model.later { model.app.addFromPost(link: link) }
                }
            }
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Sources

struct SourcesPage: View {
    @ObservedObject var model: UIModel

    var body: some View {
        let groups = model.sourceGroups()
        let rows = groups.flatMap(\.rows)
        ListAndDetail(showingDetail: model.selectedSource != nil, back: "Sources", close: { model.selectedSource = nil }) {
            VStack(spacing: 0) {
                List(selection: $model.selectedSource) {
                    ForEach(groups) { g in
                        DisclosureGroup(isExpanded: model.expanded(g.name)) {
                            ForEach(g.rows) { SourceRowView(row: $0).tag($0.id) }
                        } label: {
                            SourceGroupHeader(group: g, model: model)
                        }
                    }
                }
                Divider()
                HStack(spacing: 0) {
                    Button { model.showAdd = true } label: { Image(systemName: "plus").frame(width: 24, height: 20) }
                        .help("Add a source or a ride")
                    Divider().frame(height: 16)
                    Button { if let id = model.selectedSource { model.later { model.app.removeSource(id) } } } label: {
                        Image(systemName: "minus").frame(width: 24, height: 20)
                    }
                    .help(model.removable(model.selectedSource) ? "Remove the selected source" : "Select a source to remove it")
                    .disabled(!model.removable(model.selectedSource))
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
        } detail: {
            Group {
                if let id = model.selectedSource, let row = rows.first(where: { $0.id == id }) {
                    SourceDetail(row: row, model: model)
                } else {
                    EmptyState(text: "Choose a source to see its options.",
                               detail: "Use + to add a website, forum, calendar, Meetup group, Facebook event, Instagram account or chat.")
                }
            }
        }
        .navigationTitle("Sources")
    }
}

struct SourceRowView: View {
    let row: UIModel.SourceRow

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: row.symbol).frame(width: 20).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                // Under its app's heading, "(WhatsApp via Beeper)" would just repeat the heading.
                Text(row.name.replacingOccurrences(of: " (\(row.group) via Beeper)", with: "")).lineLimit(1)
                Text(row.problem != nil ? "Problem: " + row.problem! : row.status)
                    .font(.caption)
                    .foregroundStyle(row.problem != nil ? Color.orange : Color.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if row.rides > 0 {
                Text("\(row.rides)").font(.caption).monospacedDigit()
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                    .help("\(row.rides) upcoming ride\(row.rides == 1 ? "" : "s")")
            }
        }
        .padding(.vertical, 2)
    }
}

struct SourceGroupHeader: View {
    let group: UIModel.SourceGroup
    @ObservedObject var model: UIModel

    var body: some View {
        let feeds = group.rows.filter { $0.interval != nil }
        let intervals = Set(feeds.compactMap(\.interval))
        HStack(spacing: 8) {
            Image(systemName: group.symbol).frame(width: 18).foregroundStyle(.secondary)
            PatchLabel(text: group.name, count: group.rows.count)
            Spacer()
            if group.rows.contains(where: { $0.problem != nil }) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange).help("A source here has a problem")
            }
            if intervals.count == 1, let m = intervals.first {
                Text(m == 0 ? "Manual" : Feed.describe(m).replacingOccurrences(of: "Every ", with: "every ").replacingOccurrences(of: " minutes", with: " min"))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .contextMenu {
            if !feeds.isEmpty {
                Menu("Check all \(group.name) sources") {
                    ForEach(Feed.intervals, id: \.self) { m in
                        Button(Feed.describe(m)) { model.setInterval(m, for: feeds.map(\.id)) }
                    }
                }
            }
        }
    }
}

struct SourceDetail: View {
    let row: UIModel.SourceRow
    @ObservedObject var model: UIModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: row.symbol).font(.system(size: 28)).foregroundStyle(.secondary).frame(width: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name).font(.title2).fontWeight(.semibold).lineLimit(2)
                        Text(row.kindName).foregroundStyle(.secondary)
                    }
                }
                Label(row.interval.map { $0 > 0 ? "Updates automatically " + Feed.describe($0).lowercased()
                                                 : "Updates only when you click Check now" } ?? "You check this one yourself",
                      systemImage: row.automatic ? "arrow.triangle.2.circlepath" : "hand.point.up.left")
                    .font(.callout)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background((row.automatic ? Color.green : Color.blue).opacity(0.14), in: Capsule())

                if let p = row.problem {
                    Label(p, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                }

                switch row.kind {
                case .feed(let kind): FeedOptions(id: row.id, kind: kind, status: row.status, model: model)
                case .instagram: InstagramOptions(handle: String(row.id.dropFirst("instagram:".count)), model: model)
                case .facebook: FacebookOptions(model: model)
                case .yours: YourOptions(model: model)
                }

                if row.kind != .instagram {
                    CrewLinksEditor(key: row.id, model: model)
                    SourceRides(rides: model.rides(fromSource: row.id), model: model)
                }

                if model.removable(row.id) {
                    Divider()
                    Button("Remove…", role: .destructive) { model.later { model.app.removeSource(row.id) } }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct FeedOptions: View {
    let id: String
    let kind: FeedKind
    let status: String
    @ObservedObject var model: UIModel
    @StateObject private var name = Box("")

    @ViewBuilder func buttons(_ feed: Feed) -> some View {
        let app = model.app
        Button {
            Task { await app.checkFeed(id) }
        } label: {
            if app.checking.contains(id) { ProgressView().controlSize(.small) } else { Text("Check now") }
        }
        .disabled(app.checking.contains(id) || app.refreshing)
        if kind == .chat {
            Button("Open chat") { app.open(Beeper.chatLink(chatID: Beeper.chatID(of: feed))) }
            Button("Change chats…") { model.later { Task { await app.setUpBeeper() } } }
        } else {
            if let g = feed.groupURL {
                Button(g.contains("meetup.com") ? "Join group" : "Open website") { app.open(g) }
            } else if kind != .calendar {
                Button("Open website") { app.open(feed.url) }
            }
        }
    }

    var body: some View {
        let app = model.app
        if let feed = model.feed(id) {
            VStack(alignment: .leading, spacing: 12) {
                Text(status).foregroundStyle(.secondary)
                // In a row when there's room, otherwise one under another (never cut off).
                ViewThatFits(in: .horizontal) {
                    HStack { buttons(feed) }
                    VStack(alignment: .leading, spacing: 8) { buttons(feed) }
                }

                Picker("Check for new rides", selection: Binding(
                    get: { feed.interval },
                    set: { model.setInterval($0, for: [id]) })) {
                    ForEach(Feed.intervals, id: \.self) { m in
                        Text(Feed.describe(m) + (m == Feed.defaultInterval(kind) ? " (usual)" : "")).tag(m)
                    }
                }
                .fixedSize()

                switch kind {
                case .chat:
                    Text("RollCall reads new messages in this chat while Beeper is open. Only messages that plan a ride count: they say when, and where or who's coming. Ride talk without a day goes to Posts to look at.")
                        .font(.callout).foregroundStyle(.secondary)
                case .forum:
                    Text("New threads are read once each. Threads made from the forum's calendar have exact times; for other threads the date is read from the post (marked with a ? on the date).")
                        .font(.callout).foregroundStyle(.secondary)
                default:
                    EmptyView()
                }

                if kind == .webpage || kind == .posts || kind == .forum || id == FeedLinks.facebookCalendarID {
                    Toggle("Only keep motorbike rides and events", isOn: Binding(
                        get: { feed.keywordFilter ?? false },
                        set: { on in model.setFeed(id) { $0.keywordFilter = on } }))
                }

                HStack {
                    Text("Name").foregroundStyle(.secondary)
                    TextField("Name", text: $name.value, onCommit: {
                        let n = name.value.trimmingCharacters(in: .whitespaces)
                        if !n.isEmpty { model.setFeed(id) { $0.name = n } }
                    })
                    .textFieldStyle(.roundedBorder)
                }
                .onAppear { name.value = feed.name }
                .onChange(of: id) { _, _ in name.value = model.feed(id)?.name ?? "" }

                if kind != .chat {
                    Text(feed.url).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(2)
                }
            }
        }
    }
}

struct InstagramOptions: View {
    let handle: String
    @ObservedObject var model: UIModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Instagram doesn't let apps read posts, so RollCall opens the account in your browser and remembers when you last looked. Spot a ride? Copy the caption and use Paste post.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Open Instagram") { model.app.openInstagram(handle) }
                Button("Paste post…") { model.later { model.app.addFromPost() } }
            }
        }
    }
}

struct FacebookOptions: View {
    @ObservedObject var model: UIModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FacebookCalendarBox(app: model.app, connected: model.app.facebookCalendarConnected, later: model.later)
            Divider()
            Text("Or add one event at a time").font(.headline)
            Text("For events you haven't responded to, or if the calendar link stops working: paste the event's link with +, then download the event from Facebook and RollCall fills in the details.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Add event…") { model.later { model.app.addFacebookEvent() } }
            Toggle("Pick up Facebook event downloads from the Downloads folder", isOn: Binding(
                get: { model.store.state.settings.watchDownloads },
                set: { model.app.setWatchDownloads($0) }))
        }
    }
}

/// Connecting Facebook's calendar of the events you've responded to, in setup and on the Sources page.
struct FacebookCalendarBox: View {
    let app: AppDelegate
    let connected: Bool
    let later: (@escaping @MainActor () -> Void) -> Void
    @StateObject private var link = Box("")

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Facebook events").font(.headline)
            if connected {
                Label("Connected. Bike events you're Going or Interested in on Facebook come in by themselves.",
                      systemImage: "checkmark.circle.fill")
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    TextField("Facebook calendar link", text: $link.value, prompt: Text("Paste a new link to replace it"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(connect)
                    Button("Replace", action: connect).disabled(link.value.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Disconnect") { later { app.removeSource(FeedLinks.facebookCalendarID) } }
                }
                Text("It's also listed under Facebook on the Sources page.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Facebook can share a private calendar of the events you're Going or Interested in, so they come in by themselves:")
                    .fixedSize(horizontal: false, vertical: true)
                Text("1. Click Open Facebook Events (sign in if asked).\n2. Find “Add to calendar” on the Events page.\n3. Right-click it and choose “Copy Link”.\n4. Paste the link below and click Connect.")
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Facebook Events") { app.open("https://www.facebook.com/events/") }
                HStack {
                    TextField("Facebook calendar link", text: $link.value, prompt: Text("https://www.facebook.com/events/ical/upcoming/…"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(connect)
                    Button("Connect", action: connect).disabled(link.value.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text("Keep this link to yourself: anyone who has it can see your events. Only bike events are kept.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    func connect() {
        let s = link.value
        later { app.connectFacebookCalendar(link: s) }
        if connected { link.value = "" }
    }
}

struct YourOptions: View {
    @ObservedObject var model: UIModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rides you typed in, pasted from a post or message, or imported from a calendar file. These always show, however far away they are.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Type ride…") { model.later { model.app.addManual() } }
                Button("Paste post…") { model.later { model.app.addFromPost() } }
                Button("Import file…") { model.later { model.app.importICS() } }
            }
        }
    }
}

struct SourceRides: View {
    let rides: [RideEvent]
    @ObservedObject var model: UIModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PatchLabel(text: rides.isEmpty ? "No upcoming rides from here" : "Upcoming rides", count: rides.isEmpty ? nil : rides.count)
            ForEach(rides.prefix(12), id: \.id) { r in
                Button {
                    model.reveal(ride: r.id)
                } label: {
                    HStack(spacing: 10) {
                        DateBadge(date: r.start, decision: model.store.decision(r.id), needsCheck: r.needsCheck == true, scale: 0.75)
                        Text(r.title).lineLimit(1)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Add

struct AddSheet: View {
    @ObservedObject var model: UIModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var link = Box("")

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add").font(.title2).fontWeight(.semibold)
            VStack(alignment: .leading, spacing: 6) {
                Text("Paste a link")
                    .font(.headline)
                TextField("https://…  or  @instagramaccount", text: $link.value, onCommit: go)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 460)
                Text("Works with a club or event website, a forum section, a Meetup group, a calendar link, a news feed, a Facebook event, or an Instagram account or post. RollCall works out what it is.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Add link", action: go)
                    .keyboardShortcut(.defaultAction)
                    .disabled(link.value.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Divider()
            Text("Or").font(.headline)
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    choice("bubble.left.and.bubble.right", "Check chats", "WhatsApp, Messenger and more, through Beeper") {
                        Task { await model.app.setUpBeeper() }
                    }
                    choice("doc.on.clipboard", "Paste a post or message", "Reads the date and place from the text") {
                        model.app.addFromPost()
                    }
                }
                GridRow {
                    choice("square.and.pencil", "Type a ride in", "Name, time and meeting place") {
                        model.app.addManual()
                    }
                    choice("calendar.badge.plus", "Import a calendar file", "An .ics file someone sent you") {
                        model.app.importICS()
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 560)
        .onAppear {
            let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if clip.hasPrefix("http"), !clip.contains(where: \.isWhitespace) { link.value = clip }
        }
    }

    func go() {
        let l = link.value
        guard !l.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        dismiss()
        model.page = .sources
        model.later { model.app.add(link: l) }
    }

    func choice(_ symbol: String, _ title: String, _ detail: String, action: @escaping @MainActor () -> Void) -> some View {
        Button {
            dismiss()
            model.later(action)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.title2).frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).fontWeight(.medium)
                    Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Settings

struct SettingsPage: View {
    @ObservedObject var model: UIModel
    @StateObject private var place = Box("")
    @StateObject private var km = Box("")
    @StateObject private var days = Box("")
    @StateObject private var message = Box<String?>(nil)
    @StateObject private var saving = Box(false)

    var body: some View {
        let app = model.app
        Form {
            // Saves by itself, like the rest of Settings: numbers as you type, the place when you press Return
            // or leave the page (it's looked up on a map, so not on every keystroke).
            Section("Home area") {
                TextField("Suburb or town", text: $place.value)
                    .onSubmit(savePlace)
                TextField("Show rides within (km)", text: $km.value)
                    .onChange(of: km.value) { _, _ in saveNumbers() }
                TextField("Days ahead to show", text: $days.value)
                    .onChange(of: days.value) { _, _ in saveNumbers() }
                HStack(spacing: 6) {
                    if saving.value {
                        ProgressView().controlSize(.small)
                        Text("Looking up “\(place.value)”…").foregroundStyle(.secondary)
                    } else if let m = message.value {
                        Label(m, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    } else if let found = foundPlace {
                        Label("Found: " + found, systemImage: "checkmark.circle.fill")
                    }
                }
                .font(.callout)
                Text("Press Return after changing the suburb. Rides further away are hidden, except rides you add yourself, rides from your chats and your Facebook events.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Section("Chats") {
                LabeledContent("Beeper", value: Keychain.read() == nil ? "Not connected" : "Connected (read only)")
                Button(Keychain.read() == nil ? "Connect Beeper…" : "Choose chats…") {
                    model.later { Task { await app.setUpBeeper() } }
                }
            }
            Section("Facebook") {
                FacebookCalendarBox(app: app, connected: app.facebookCalendarConnected, later: model.later)
                Toggle("Pick up Facebook event downloads automatically", isOn: Binding(
                    get: { model.store.state.settings.watchDownloads }, set: { app.setWatchDownloads($0) }))
            }
            Section("Riding together") {
                TogetherForm(app: app)
            }
            Section("General") {
                Toggle("Open RollCall when you log in", isOn: Binding(
                    get: { app.opensAtLogin }, set: { app.setOpensAtLogin($0) }))
                Button("Open calendar") { app.openCalendarApp() }
                Button("Run setup…") { model.later { app.showSetup() } }
            }
            Section("Privacy") {
                Text("Your rides, chats and settings stay on this Mac, readable only by you. RollCall has no accounts, no tracking and no online AI, and it never posts or sends messages. Removing a chat also removes what RollCall kept from it.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Privacy details") { app.open("https://github.com/MadisonDayerson/RollCall#your-privacy") }
                    Button("Delete all data…", role: .destructive) { model.later { app.deleteAllData() } }
                }
            }
            Section("Updates") {
                LabeledContent("Version", value: Updater.currentVersion)
                Toggle("Check for new versions automatically", isOn: Binding(
                    get: { model.store.state.settings.checkForUpdates ?? true },
                    set: { model.store.state.settings.checkForUpdates = $0; model.store.save() }))
                HStack {
                    Button("Check now") { model.later { Task { await app.checkForUpdates(manual: true) } } }
                    Button("Release notes") { app.open(Updater.releasesPage) }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onAppear(perform: load)
        .onDisappear(perform: savePlace)
    }

    /// "Footscray, VIC, Australia" once the home area has been found on the map.
    var foundPlace: String? {
        let st = model.store.state.settings
        let parts = [st.homeCity, st.homeRegion, st.homeCountry].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    func saveNumbers() {
        let st = model.store.state.settings
        guard let k = Double(km.value), k > 0, let d = Int(days.value), d > 0,
              k != st.radiusKm || d != st.daysAhead else { return }
        Task { _ = await model.app.setHomeArea(place: st.homeName, km: k, days: d) }
    }

    func savePlace() {
        let p = place.value.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty, !saving.value, p != model.store.state.settings.homeName || model.store.state.settings.homeRegion == nil else { return }
        saving.value = true
        message.value = nil
        Task {
            message.value = await model.app.setHomeArea(place: p, km: 0, days: 0)
            if message.value == nil { place.value = model.store.state.settings.homeName }  // just the suburb
            saving.value = false
        }
    }

    func load() {
        let s = model.store.state.settings
        place.value = s.homeName
        km.value = String(Int(s.radiusKm))
        days.value = String(s.daysAhead)
    }
}

// MARK: - Riding together

/// Before, during and after a ride: invite the crew, keep in touch on the day, and share footage under one tag.
struct RideTogether: View {
    let ride: RideEvent
    @ObservedObject var model: UIModel
    @StateObject private var tag = Box("")
    @StateObject private var copied = Box<String?>(nil)

    var body: some View {
        let app = model.app
        let crew = model.store.state.settings.crew
        let discord = Crew.discord(together: crew, links: app.links(ride))
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Ride tags").foregroundStyle(.secondary)
                    TextField("#RC…", text: $tag.value, onCommit: { app.setRideTag(ride.id, tag.value) })
                        .textFieldStyle(.roundedBorder).frame(maxWidth: 360)
                    if model.store.state.rideTags[ride.id] != nil {
                        Button("Reset") { app.setRideTag(ride.id, ""); tag.value = app.rideTags(ride) }
                    }
                }
                Text(past ? "The first tag is the ride's code (#RC and the date), the same for everyone using RollCall, so your footage ends up with everyone else's. The rest name the club, place or occasion; change them if you like."
                     : "The first tag is the ride's code (#RC and the date), the same for everyone using RollCall, so posts end up together. The rest name the club, place or occasion; change them if you like. They're in the invite, the calendar event and the caption.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

                if past {
                    PatchLabel(text: "After").padding(.top, 4)
                    after
                    if let d = discord {
                        HStack { Button("Open Discord") { app.open(d) } }
                    }
                } else {
                PatchLabel(text: "Before").padding(.top, 4)
                HStack {
                    Button("Invite…") { app.shareInvite(ride) }
                        .help("Send the details and a calendar file with Messages, AirDrop, Mail and more")
                    Button("Copy invite") { app.copy(app.invite(ride)); copied.value = "Invite copied: paste it into Discord, WhatsApp or any group chat." }
                }
                PatchLabel(text: "During").padding(.top, 4)
                HStack {
                    if let d = discord { Button("Open Discord") { app.open(d) } }
                    if crew.locationApp == .findMy { Button("Open Find My") { app.openFindMy() } }
                    if !ride.location.isEmpty { Button("Directions") { app.openMaps(place: ride.location) } }
                }
                Text(duringNote(crew, discord: discord)).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                PatchLabel(text: "After").padding(.top, 4)
                after
                }
                if let c = copied.value { Label(c, systemImage: "doc.on.clipboard").font(.callout) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Ride with friends", systemImage: "person.2.wave.2")
        }
        .onAppear { tag.value = app.rideTags(ride); copied.value = nil }
        .onChange(of: ride.id) { _, _ in tag.value = app.rideTags(ride); copied.value = nil }
    }

    var past: Bool { model.isPast(ride) }

    var after: some View {
        let app = model.app
        let buttons = Group {
            Button("Share footage…") { app.shareFootage(ride) }
                .help("Pick photos or videos and send them with the caption and tags")
            Button("Copy caption") { app.copy(app.caption(ride)); copied.value = "Caption copied: paste it into Instagram, TikTok, YouTube or Facebook." }
            Menu("See posts") {
                ForEach(Crew.tagPages(app.rideTag(ride)), id: \.name) { p in Button(p.name) { app.open(p.url) } }
            }
            .fixedSize()
        }
        // Side by side when there's room, stacked in a narrow window.
        return ViewThatFits(in: .horizontal) {
            HStack { buttons }.fixedSize()
            VStack(alignment: .leading) { buttons }
        }
    }

    func duringNote(_ crew: Together, discord: String?) -> String {
        var parts: [String] = []
        if crew.intercom != .none {
            let g = crew.intercomGroup.trimmingCharacters(in: .whitespaces)
            parts.append("\(crew.intercom.name)\(g.isEmpty ? "" : " (\(g))") pairs on your phone and helmet; the group is in the invite.")
        }
        if crew.locationApp != .none, crew.locationApp != .findMy {
            parts.append("Location sharing is in \(crew.locationApp.name) on your phone; the invite reminds everyone to switch it on.")
        }
        if discord == nil { parts.append("Add your crew's Discord link in Settings → Riding together to get a button here.") }
        return parts.joined(separator: " ")
    }
}

/// Location sharing, intercom, Discord and tags, used in setup and Settings. Saves by itself.
struct TogetherForm: View {
    let app: AppDelegate
    @StateObject private var t = Box(Together())
    @StateObject private var loaded = Box(false)
    @StateObject private var pending = Box<Task<Void, Never>?>(nil)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Share locations with", selection: $t.value.locationApp) {
                ForEach(LocationApp.allCases, id: \.self) { Text($0.name).tag($0) }
            }
            Picker("Intercom", selection: $t.value.intercom) {
                ForEach(Intercom.allCases, id: \.self) { Text($0.name).tag($0) }
            }
            if t.value.intercom != .none {
                TextField("Intercom group (optional)", text: $t.value.intercomGroup, prompt: Text("e.g. DMC group SUNDAY CREW"))
            }
            TextField("Discord invite link", text: $t.value.discord, prompt: Text("https://discord.gg/…"))
            TextField("Tags you post under", text: $t.value.tags, prompt: Text("#hooligoon #melbourneriders"))
            TextField("Your handle (for captions)", text: $t.value.handle, prompt: Text("@yourname"))
            Text("Invites, calendar events and captions include these. Groups can have their own Discord and tags on the Sources page.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { if !loaded.value { t.value = app.store.state.settings.crew; loaded.value = true } }
        // Saves by itself a moment after you stop typing (the calendar is updated too, so not on every key).
        .onChange(of: t.value) { _, v in
            pending.value?.cancel()
            pending.value = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 800_000_000)
                if !Task.isCancelled { app.setTogether(v) }
            }
        }
        .onDisappear { pending.value?.cancel(); app.setTogether(t.value) }
    }
}

/// A group's own Discord and tags, on its Sources page.
struct CrewLinksEditor: View {
    let key: String
    @ObservedObject var model: UIModel
    @StateObject private var discord = Box("")
    @StateObject private var tags = Box("")
    @StateObject private var pending = Box<Task<Void, Never>?>(nil)

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Discord invite link", text: $discord.value, prompt: Text("Uses yours from Settings if empty"))
                    .textFieldStyle(.roundedBorder)
                TextField("Tags", text: $tags.value, prompt: Text("e.g. #hooligoon"))
                    .textFieldStyle(.roundedBorder)
                Text("Added to invites, calendar events and captions for this group's rides.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } label: {
            Label("Riding with this group", systemImage: "person.2.wave.2")
        }
        .onAppear(perform: load)
        .onChange(of: key) { old, _ in
            // Picking another source reuses this view, so keep what was typed for the last one.
            pending.value?.cancel()
            model.app.setCrewLinks(old, CrewLinks(discord: discord.value, tags: tags.value))
            load()
        }
        // Saves by itself a moment after you stop typing.
        .onChange(of: discord.value) { _, _ in saveSoon() }
        .onChange(of: tags.value) { _, _ in saveSoon() }
        .onDisappear { pending.value?.cancel(); save() }
    }

    func load() {
        let l = model.store.state.crew[key]
        discord.value = l?.discord ?? ""
        tags.value = l?.tags ?? ""
    }

    func save() { model.app.setCrewLinks(key, CrewLinks(discord: discord.value, tags: tags.value)) }

    func saveSoon() {
        pending.value?.cancel()
        let k = key, l = CrewLinks(discord: discord.value, tags: tags.value)
        pending.value = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            if !Task.isCancelled { model.app.setCrewLinks(k, l) }
        }
    }
}

// MARK: - Layout

/// A list beside its details when there's room. In a narrow window (a quarter of the screen, say)
/// the list fills the window and choosing an item shows its details with a Back button.
struct ListAndDetail<ListContent: View, Detail: View>: View {
    var showingDetail: Bool
    var back: String
    var close: () -> Void
    @ViewBuilder var list: ListContent
    @ViewBuilder var detail: Detail

    /// Below this width the two columns would be cramped.
    static var sideBySide: CGFloat { 600 }

    var body: some View {
        GeometryReader { g in
            if g.size.width >= Self.sideBySide {
                // The details get the larger share: the list starts at about 40% and can't be dragged past
                // half, so the details always have room for their buttons.
                HSplitView {
                    list.frame(minWidth: 250, idealWidth: max(250, g.size.width * 0.4), maxWidth: max(250, g.size.width * 0.5))
                    detail.frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if showingDetail {
                VStack(spacing: 0) {
                    HStack {
                        Button(action: close) { Label(back, systemImage: "chevron.left") }
                            .buttonStyle(.borderless)
                        Spacer()
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    Divider()
                    detail.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                list.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
