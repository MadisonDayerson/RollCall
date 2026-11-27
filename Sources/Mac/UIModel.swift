import SwiftUI
import AppKit

/// What the window shows, kept in step with the saved state.
@MainActor
final class UIModel: ObservableObject {
    enum Page: String, Hashable, CaseIterable {
        case home, rides, review, sources, settings
    }

    unowned let app: AppDelegate
    @Published var page: Page = .home
    /// The Add sheet that's open, if any.
    @Published var adding: AddKind?
    @Published var selectedSource: String?
    @Published var selectedRide: String?
    @Published var selectedReview: String?
    /// The plan Apple Intelligence is reading for the Add ride form.
    @Published var readingReview: String?
    /// List, week or month, remembered like the iPhone's.
    @Published var ridesLayout = RidesLayout(rawValue: UserDefaults.standard.string(forKey: "ridesLayout") ?? "") ?? .list {
        didSet { UserDefaults.standard.set(ridesLayout.rawValue, forKey: "ridesLayout") }
    }
    /// The day the week or month is at, and whether only that day's rides are listed.
    @Published var calendarDay = Date()
    @Published var oneDay = false
    /// Ride id -> more details Refresh is looking for, while it looks and what it found (until RollCall quits).
    @Published var lookups: [String: RideSearch.Lookup] = [:]
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

    func section(of id: String) -> RideGroup? { store.groupedRides().first { $0.rides.contains { $0.id == id } }?.group }

    /// Skipped and Past start folded away; whatever the person opens or closes is remembered.
    @Published var closedRideSections = Set((UserDefaults.standard.stringArray(forKey: "closedRideSections") ?? ["Skipped", "Past"])
        .map { $0 == "Upcoming" ? "Undecided" : $0 }) {  // "Upcoming" was the section's old name
        didSet { UserDefaults.standard.set(Array(closedRideSections).sorted(), forKey: "closedRideSections") }
    }

    func rideSectionOpen(_ name: String) -> Binding<Bool> {
        Binding(get: { !self.closedRideSections.contains(name) },
                set: { open in if open { self.closedRideSections.remove(name) } else { self.closedRideSections.insert(name) } })
    }

    /// Shows a ride on the Rides page, opening its section in the list.
    func reveal(ride id: String) {
        ridesLayout = .list
        if let s = section(of: id) { closedRideSections.remove(s.rawValue) }
        selectedRide = id
        page = .rides
    }

    /// Shows a day's rides on the Rides page, in the week (or the month, if that's showing), with the first one's details.
    func show(day: Date) {
        calendarDay = day
        oneDay = true
        if ridesLayout == .list { ridesLayout = .week }
        selectedRide = RideCalendar.byDay(store.calendarRides())[Calendar.current.startOfDay(for: day)]?.first?.id
        page = .rides
    }

    func isPast(_ ride: RideEvent) -> Bool { ride.finish < Date() }

    var undecidedCount: Int { store.upcoming().filter { store.decision($0.id) == .undecided }.count }

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

    func removable(_ id: String) -> Bool { id != "facebook" && id != "yours" }
}
