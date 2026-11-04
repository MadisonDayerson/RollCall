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
            case .past: return "Rides you mark Going move here once they're over."
            }
        }
    }

    unowned let app: AppDelegate
    @Published var page: Page = .rides
    @Published var showAdd = false
    @Published var selectedSource: String?
    @Published var selectedRide: String?
    @Published var selectedReview: String?
    /// The plan Apple Intelligence is reading for the Add ride form.
    @Published var readingReview: String?
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

    func isPast(_ ride: RideEvent) -> Bool { ride.finish < Date() }

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
        store.upcoming(oneEach: false).filter { id == "yours" ? Self.yourSources.contains($0.source) : $0.source == id }
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
