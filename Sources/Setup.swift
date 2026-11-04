import SwiftUI
import AppKit
import EventKit
import UserNotifications

/// The first-run wizard: home area, chats (through Beeper), groups and accounts to follow, and a calendar.
/// Every step can be skipped, and "Set up RollCall…" in the menu opens it again.
@MainActor
final class SetupModel: ObservableObject {
    enum Step: Int, CaseIterable {
        case welcome, home, messages, accounts, calendar, together, finish
        var title: String {
            switch self {
            case .welcome: return "Welcome"
            case .home: return "Your area"
            case .messages: return "Chats"
            case .accounts: return "Groups & accounts"
            case .calendar: return "Calendar"
            case .together: return "Riding together"
            case .finish: return "All set"
            }
        }
    }

    enum BeeperState: Equatable {
        case checking, notInstalled, closed, notConnected, connected(watching: Int)
    }

    unowned let app: AppDelegate
    @Published var step: Step = .welcome
    @Published var beeper: BeeperState = .checking
    @Published var calendarStatus = EKEventStore.authorizationStatus(for: .event)
    @Published var notificationsAllowed: Bool?
    private var observer: NSObjectProtocol?

    init(app: AppDelegate) {
        self.app = app
        observer = NotificationCenter.default.addObserver(forName: Store.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.objectWillChange.send() }
        }
    }

    var store: Store { app.store }
    var settings: Settings { store.state.settings }

    func go(_ s: Step) {
        step = s
        if s != .messages, guide != nil { leaveGuide() }
        if s == .messages { Task { await checkBeeper() } }
        if s == .calendar { checkCalendar() }
        if s == .finish { Task { await checkNotifications() } }
    }
    func next() { if let s = Step(rawValue: step.rawValue + 1) { go(s) } }
    func back() { if let s = Step(rawValue: step.rawValue - 1) { go(s) } }

    /// Runs an action after the current click finishes, so dialogs don't open mid-click.
    func later(_ action: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async { MainActor.assumeIsolated { action() } }
    }

    // MARK: Home

    /// "Ringwood, Victoria, Australia" once the home area has been found.
    var foundPlace: String? {
        let parts = [settings.homeCity, settings.homeRegion, settings.homeCountry].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    // MARK: Messages

    static let beeperApp = "com.automattic.beeper.desktop"
    static let beeperDownload = "https://www.beeper.com/download"

    func checkBeeper() async {
        let watching = store.state.feeds.filter { $0.type == .chat }.count
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.beeperApp) == nil {
            beeper = .notInstalled
        } else if !(await Beeper.isRunning()) {
            beeper = .closed
        } else if Keychain.read() == nil {
            beeper = .notConnected
        } else {
            beeper = .connected(watching: watching)
        }
    }

    func openBeeper() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.beeperApp) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func chooseChats() {
        later {
            Task {
                await self.app.setUpBeeper()
                await self.checkBeeper()
            }
        }
    }

    // MARK: Beeper guide

    /// A step-by-step guide inside the Chats step, for people new to Beeper.
    enum GuideStep: Int, CaseIterable {
        case download, open, accounts, api, connect, done
        static let counted = 5  // "Step 3 of 5"; done isn't counted
    }

    @Published var guide: GuideStep?
    @Published var beeperInstalled = false
    @Published var beeperOpen = false
    @Published var apiOn = false
    private var watcher: Task<Void, Never>?

    var watchingChats: Int { store.state.feeds.filter { $0.type == .chat }.count }

    func startGuide() {
        Task {
            await lookAtBeeper()
            // Start at the first thing not done yet.
            guide = !beeperInstalled ? .download : !beeperOpen ? .open : !apiOn ? .accounts
                : (Keychain.read() == nil || watchingChats == 0) ? .connect : .done
            watchBeeper()
        }
    }

    func leaveGuide() {
        guide = nil
        watcher?.cancel()
        Task { await checkBeeper() }
    }

    func guideNext() { if let g = guide, let n = GuideStep(rawValue: g.rawValue + 1) { guide = n } }
    func guideBack() { if let g = guide, let n = GuideStep(rawValue: g.rawValue - 1) { guide = n } }

    func lookAtBeeper() async {
        beeperInstalled = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.beeperApp) != nil
        beeperOpen = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.beeperApp).isEmpty
        apiOn = beeperOpen ? await Beeper.isRunning() : false
    }

    /// Checks every couple of seconds and moves on by itself when a step is clearly done.
    func watchBeeper() {
        watcher?.cancel()
        watcher = Task {
            while !Task.isCancelled, guide != nil {
                await lookAtBeeper()
                if guide == .download, beeperInstalled { guide = .open }
                if guide == .api, apiOn { guide = .connect }
                if guide == .connect, Keychain.read() != nil, watchingChats > 0 { guide = .done }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    func bringBeeperForward() {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: Self.beeperApp).first {
            running.activate()
        } else {
            openBeeper()
        }
    }

    func openDownloads() {
        if let d = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first { NSWorkspace.shared.open(d) }
    }

    func connectFromGuide() {
        later {
            Task {
                await self.app.setUpBeeper()
                await self.checkBeeper()
                if Keychain.read() != nil, self.watchingChats > 0 { self.guide = .done }
            }
        }
    }

    // MARK: Groups and accounts

    var suggestions: (feeds: [Feed], instagram: [InstagramAccount]) { Starter.suggestions(for: settings) }

    func following(_ f: Feed) -> Binding<Bool> {
        Binding(get: { self.store.state.feeds.contains { $0.id == f.id } }, set: { on in
            if on {
                guard !self.store.state.feeds.contains(where: { $0.id == f.id }) else { return }
                self.store.state.feeds.append(f)
                self.store.save()
                Task { await self.app.checkFeed(f.id) }
            } else {
                self.app.forgetFeed(f.id)
                self.store.save()
            }
        })
    }

    func following(_ a: InstagramAccount) -> Binding<Bool> {
        Binding(get: { self.store.state.instagram.contains { $0.handle == a.handle } }, set: { on in
            if on {
                if !self.store.state.instagram.contains(where: { $0.handle == a.handle }) { self.store.state.instagram.append(a) }
            } else {
                self.store.state.instagram.removeAll { $0.handle == a.handle }
            }
            self.store.save()
        })
    }

    /// Everything followed so far, chats aside (those are on the Chats step).
    var followed: [(id: String, name: String, symbol: String)] {
        store.state.feeds.filter { $0.type != .chat }.map { ($0.id, $0.name, "globe") }
            + store.state.instagram.map { ("instagram:" + $0.handle, "@" + $0.handle, "camera") }
    }

    // MARK: Calendar

    func checkCalendar() {
        calendarStatus = EKEventStore.authorizationStatus(for: .event)
        app.calendar.eventStore.reset()
        objectWillChange.send()
    }

    func allowCalendar() {
        Task {
            if calendarStatus == .denied || calendarStatus == .restricted {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
            } else {
                _ = await app.calendar.requestAccess()
            }
            checkCalendar()
        }
    }

    var calendarAllowed: Bool { calendarStatus == .fullAccess }

    /// The current step has been filled in, so there's nothing to skip.
    var stepDone: Bool {
        switch step {
        case .messages: if case .connected(let n) = beeper { return n > 0 } else { return false }
        case .accounts: return !followed.isEmpty
        case .calendar: return calendarAllowed && chosenAccount != nil
        case .together: return settings.crew != Together()
        default: return false
        }
    }

    var accounts: [EKSource] { calendarAllowed ? app.calendar.accounts() : [] }

    var hasGoogle: Bool { accounts.contains { Self.isGoogle($0) } }

    static func isGoogle(_ s: EKSource) -> Bool {
        s.sourceType == .calDAV && (s.title.lowercased().contains("gmail") || s.title.lowercased().contains("google")
                                    || s.title.contains("@") && !s.title.lowercased().contains("icloud"))
    }

    /// Which account the RollCall calendar goes in: the one picked, or the one it would use anyway.
    var chosenAccount: String? {
        settings.calendarSourceID
            ?? app.calendar.existingCalendar()?.source.sourceIdentifier
            ?? accounts.first { $0.sourceType == .calDAV && $0.title.lowercased().contains("icloud") }?.sourceIdentifier
            ?? accounts.first?.sourceIdentifier
    }

    func choose(_ s: EKSource) {
        store.state.settings.calendarSourceID = s.sourceIdentifier
        app.calendar.preferredSourceID = s.sourceIdentifier
        store.save()
    }

    static func describe(_ s: EKSource) -> (name: String, detail: String, symbol: String) {
        let t = s.title.lowercased()
        switch s.sourceType {
        case .local: return ("On this Mac", "Apple Calendar on this Mac only", "desktopcomputer")
        case .exchange: return (s.title, "Microsoft Exchange or Outlook", "envelope")
        default:
            if t.contains("icloud") { return ("iCloud", "Apple Calendar, on your iPhone and other Apple devices too", "icloud") }
            if isGoogle(s) { return (s.title, "Google Calendar, everywhere you use Google", "g.circle") }
            return (s.title, "Online calendar account", "calendar")
        }
    }

    func openInternetAccounts() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension")!)
    }

    // MARK: Finish

    func checkNotifications() async {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let s = await UNUserNotificationCenter.current().notificationSettings()
        notificationsAllowed = s.authorizationStatus == .notDetermined ? nil : s.authorizationStatus == .authorized
    }

    func openNotificationSettings() {
        let id = Bundle.main.bundleIdentifier ?? ""
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
            NSWorkspace.shared.open(url)
        }
    }

    func allowNotifications() {
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            await checkNotifications()
        }
    }
}
