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

// MARK: - Views

struct SetupView: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        VStack(spacing: 0) {
            StepDots(model: model)
                .padding(.top, 18).padding(.bottom, 10)
            Divider()
            ScrollView {
                Group {
                    if model.guide != nil {
                        BeeperGuide(model: model)
                    } else {
                    switch model.step {
                    case .welcome: WelcomeStep(model: model)
                    case .home: HomeStep(model: model)
                    case .messages: MessagesStep(model: model)
                    case .accounts: AccountsStep(model: model)
                    case .calendar: CalendarStep(model: model)
                    case .together: TogetherStep(model: model)
                    case .finish: FinishStep(model: model)
                    }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 36).padding(.vertical, 24)
            }
            Divider()
            if let g = model.guide {
                GuideFooter(model: model, step: g).padding(16)
            } else {
            HStack {
                if model.step == .welcome {
                    Button("Skip setup") { model.app.finishSetup(openWindow: false) }
                } else {
                    Button("Back") { model.back() }
                }
                Spacer()
                if model.step == .finish {
                    Button("Start") { model.app.finishSetup(openWindow: true) }
                        .keyboardShortcut(.defaultAction)
                } else {
                    // Once a step is done, Continue is the only choice (no "Skip" for something already done).
                    if ![.welcome, .home].contains(model.step) && !model.stepDone {
                        Button("Skip") { model.next() }
                    }
                    Button(model.step == .welcome ? "Get started" : "Continue") { model.next() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
            }
        }
        .frame(minWidth: 520, minHeight: 400)
        // Black and white, like the logo (near-black so white button text still reads in dark mode).
        .tint(Color(white: 0.12))
    }
}

struct StepDots: View {
    @ObservedObject var model: SetupModel
    var body: some View {
        HStack(spacing: 18) {
            ForEach(SetupModel.Step.allCases, id: \.self) { s in
                VStack(spacing: 5) {
                    Circle()
                        .fill(s.rawValue <= model.step.rawValue ? Color.primary : Color.secondary.opacity(0.3))
                        .frame(width: 9, height: 9)
                    Text(s.title).font(.caption2)
                        .foregroundStyle(s == model.step ? .primary : .secondary)
                }
            }
        }
    }
}

/// A heading and a line under it, used at the top of each step.
struct StepHeader: View {
    var title: String
    var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title2.bold())
            Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 8)
    }
}

/// A rounded box holding one option or explanation.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct WelcomeStep: View {
    @ObservedObject var model: SetupModel
    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 128, height: 128)
            Text("Welcome to RollCall").font(.largeTitle.bold())
            Text("RollCall finds motorbike group rides and events near you, from clubs, forums, event sites and your group chats, and puts the ones you're going to in your calendar.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 10) {
                Label("Set your home area so you only see rides nearby", systemImage: "mappin.and.ellipse")
                Label("Connect group chats (WhatsApp, Messenger, Messages and more) through Beeper", systemImage: "bubble.left.and.bubble.right")
                Label("Follow clubs, Meetup groups, forums, Instagram accounts and your Facebook events", systemImage: "person.3")
                Label("Choose Apple Calendar or Google Calendar for your rides", systemImage: "calendar")
            }
            .padding(.top, 8)
            Text("Your rides and chats stay on your Mac: no accounts, no tracking, no online AI. RollCall never posts, sends messages or RSVPs for you.")
                .font(.callout).foregroundStyle(.secondary).padding(.top, 8)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

struct HomeStep: View {
    @ObservedObject var model: SetupModel
    @StateObject private var place = Box("")
    @StateObject private var message = Box<String?>(nil)
    @StateObject private var finding = Box(false)

    static let distances = [25, 50, 100, 200, 400]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepHeader(title: "Where do you ride from?",
                       text: "RollCall shows rides within a distance of home. Rides from your own chats always show, wherever they are.")
            HStack {
                TextField("Suburb or town, e.g. Ringwood VIC", text: $place.value)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(find)
                Button("Find", action: find).disabled(place.value.trimmingCharacters(in: .whitespaces).isEmpty)
                if finding.value { ProgressView().controlSize(.small) }
            }
            if let m = message.value {
                Label(m, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            } else if let found = model.foundPlace {
                Label("Found: \(found)", systemImage: "checkmark.circle.fill").foregroundStyle(.primary)
            }
            Picker("Show rides within", selection: Binding(
                get: { Int(model.settings.radiusKm) },
                set: { km in model.store.state.settings.radiusKm = Double(km); model.store.save() })) {
                ForEach(Self.distances, id: \.self) { Text("\($0) km").tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)
            Text("You can change these later in Settings.").font(.caption).foregroundStyle(.secondary)
        }
        .onAppear {
            place.value = model.foundPlace == nil && !model.store.state.setupDone ? "" : model.settings.homeName
        }
    }

    func find() {
        finding.value = true
        Task {
            message.value = await model.app.setHomeArea(place: place.value, km: 0, days: 0, force: true)
            finding.value = false
        }
    }
}

struct MessagesStep: View {
    @ObservedObject var model: SetupModel

    static let networks: [(name: String, symbol: String, note: String)] = [
        ("WhatsApp", "phone.bubble", "Connect in Beeper by scanning a code with your phone, like WhatsApp Web."),
        ("Messenger", "message", "Sign in to Facebook inside Beeper."),
        ("Messages (iMessage and texts)", "message.badge", "On a Mac, Beeper can add your iMessages; texts from Android phones work too."),
        ("Signal, Telegram, Discord, Instagram DMs", "ellipsis.bubble", "Also available in Beeper, if your groups use them."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepHeader(title: "Connect your group chats",
                       text: "Lots of rides are planned in group chats. RollCall checks the chats you choose for messages about a ride with a day or time, and sums up the plan for you to look over.")
            Card {
                Label("We recommend Beeper", systemImage: "star.fill").font(.headline)
                Text("WhatsApp, Messenger and Messages don't let other apps read your chats. Beeper is a free app that brings them all into one place, and lets RollCall read just the chats you tick, with a read-only permission you approve. RollCall can never send, edit or delete messages, and nothing leaves your Mac.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Self.networks, id: \.name) { n in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: n.symbol).frame(width: 22).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(n.name).bold()
                            Text(n.note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            Divider()
            if model.beeper != .checking, !isConnected {
                Card {
                    Label("New to Beeper?", systemImage: "hand.wave").font(.headline)
                    Text("RollCall walks you through it one step at a time: downloading Beeper, adding your chats, and switching on the connection RollCall needs. It takes about 10 minutes, and RollCall checks each step for you.")
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Set up Beeper") { model.startGuide() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
                Text("Already use Beeper?").font(.headline).padding(.top, 4)
            }
            BeeperSteps(model: model)
        }
    }

    var isConnected: Bool { if case .connected = model.beeper { return true } else { return false } }
}

struct BeeperSteps: View {
    @ObservedObject var model: SetupModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch model.beeper {
            case .checking:
                HStack { ProgressView().controlSize(.small); Text("Looking for Beeper…") }
            case .notInstalled:
                Text("1. Download Beeper").font(.headline)
                Text("Install Beeper Desktop, open it, and sign up (it's free). Then add your chat accounts in Beeper → Settings → Accounts.")
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Download Beeper") { model.app.open(SetupModel.beeperDownload) }
                    Button("I've installed it") { Task { await model.checkBeeper() } }
                }
            case .closed:
                Text("2. Switch on Beeper's connection for apps").font(.headline)
                Text("Open Beeper, then Settings (⌘,) → Developers, and switch on Beeper Desktop API. Leave Beeper open when you want RollCall to check your chats.")
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Open Beeper") { model.openBeeper() }
                    Button("Check again") { Task { await model.checkBeeper() } }
                }
            case .notConnected:
                Text("3. Let RollCall read your chats").font(.headline)
                Text("A Beeper page opens in your browser, then Beeper asks whether RollCall may read your chats. Click Allow, then tick the chats where people post rides.")
                    .fixedSize(horizontal: false, vertical: true)
                Button("Connect to Beeper…") { model.chooseChats() }
            case .connected(let n):
                Label(n == 0 ? "Connected to Beeper. Choose the chats where people post rides."
                             : "Connected to Beeper, checking \(n) chat\(n == 1 ? "" : "s").",
                      systemImage: "checkmark.circle.fill").foregroundStyle(.primary)
                Button(n == 0 ? "Choose chats…" : "Change chats…") { model.chooseChats() }
            }
            if case .connected = model.beeper {} else {
                Text("Don't use Beeper? Skip this step. You can still paste a message into RollCall with Add whenever someone posts a ride.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct AccountsStep: View {
    @ObservedObject var model: SetupModel
    @StateObject private var link = Box("")

    var body: some View {
        let sugg = model.suggestions
        VStack(alignment: .leading, spacing: 14) {
            StepHeader(title: "Follow groups and accounts",
                       text: "Add the clubs, Meetup groups, forums, event pages and Instagram accounts you follow. RollCall checks websites and calendars by itself, and reminds you to look at Instagram.")
            if !sugg.feeds.isEmpty || !sugg.instagram.isEmpty {
                Card {
                    Text("Suggested for \(model.settings.homeCity ?? model.settings.homeName)").font(.headline)
                    ForEach(sugg.feeds, id: \.id) { f in Toggle(f.name, isOn: model.following(f)) }
                    ForEach(sugg.instagram, id: \.handle) { a in Toggle("@\(a.handle) on Instagram", isOn: model.following(a)) }
                }
            }
            Text("Add your own").font(.headline)
            HStack {
                TextField("Paste a link or an @instagram name", text: $link.value)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Add", action: add).disabled(link.value.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("Works with a club or event website, a forum section, a Meetup group, a calendar link, a news feed, or an Instagram account. Facebook doesn't let apps read groups, but it can share the events you've responded to:")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Card {
                FacebookCalendarBox(app: model.app, connected: model.app.facebookCalendarConnected, later: model.later)
                Text("You can skip this and add Facebook events one at a time later with +.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !model.followed.isEmpty {
                Text("Following").font(.headline).padding(.top, 4)
                ForEach(model.followed, id: \.id) { f in
                    HStack {
                        Image(systemName: f.symbol).frame(width: 20).foregroundStyle(.secondary)
                        Text(f.name)
                        Spacer()
                        Button { let id = f.id; model.later { model.app.removeSource(id) } } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Stop following")
                    }
                }
            }
        }
    }

    func add() {
        let s = link.value
        link.value = ""
        model.later { model.app.add(link: s) }
    }
}

struct CalendarStep: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepHeader(title: "Choose a calendar",
                       text: "When you mark a ride Going, RollCall adds it to a calendar called RollCall, with a reminder the evening before, and updates it if the plan changes.")
            if !model.calendarAllowed {
                Card {
                    Text("RollCall needs permission to use your calendars").font(.headline)
                    Text(model.calendarStatus == .denied || model.calendarStatus == .restricted
                         ? "Calendar access was turned off. In System Settings → Privacy & Security → Calendars, switch on RollCall and choose Full Access, then come back."
                         : "Your Mac will ask whether RollCall can use Calendar. Choose Allow Full Access so RollCall can update rides when plans change.")
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button(model.calendarStatus == .notDetermined ? "Allow calendar access" : "Open System Settings") { model.allowCalendar() }
                        if model.calendarStatus != .notDetermined { Button("Check again") { model.checkCalendar() } }
                    }
                }
            } else {
                Text("Put RollCall's calendar in:").font(.headline)
                ForEach(model.accounts, id: \.sourceIdentifier) { s in
                    let d = SetupModel.describe(s)
                    Button { model.choose(s) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: model.chosenAccount == s.sourceIdentifier ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(.primary)
                            Image(systemName: d.symbol).frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(d.name).bold()
                                Text(d.detail).font(.callout).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if !model.hasGoogle {
                    Card {
                        Label("Use Google Calendar", systemImage: "g.circle").font(.headline)
                        Text("RollCall adds rides to Google Calendar through your Mac's own accounts:")
                        Text("1. Open Internet Accounts and click Add Account.\n2. Choose Google and sign in.\n3. Make sure Calendars is switched on.\n4. Come back here and click Check again, then choose your Google account above.")
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Open Internet Accounts") { model.openInternetAccounts() }
                            Button("Check again") { model.checkCalendar() }
                        }
                        Text("Outlook and Exchange calendars work the same way.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear { model.checkCalendar() }
    }
}

struct TogetherStep: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepHeader(title: "Ride together",
                       text: "Tell RollCall how your crew keeps in touch. Every invite and calendar event then says which Discord and voice chat group to join and where to share locations, and every ride gets a tag so everyone's photos and videos end up together.")
            Form { TogetherForm(app: model.app) }
                .formStyle(.grouped)
                .frame(height: 300)
                .padding(.horizontal, -20)
            Text("Life360, Cardo, Instagram and TikTok don't let other apps connect to them, so RollCall can't see where friends are or post for you. It gives everyone the same details and tags instead.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct FinishStep: View {
    @ObservedObject var model: SetupModel

    func count(_ n: Int, _ one: String, _ many: String? = nil) -> String {
        "\(n) " + (n == 1 ? one : many ?? one + "s")
    }

    var body: some View {
        let s = model.store.state
        VStack(alignment: .leading, spacing: 14) {
            StepHeader(title: "You're all set", text: "RollCall lives in the menu bar, next to the clock. Click RC to see rides, or open the window for everything else.")
            Card {
                Label(model.foundPlace.map { "Rides within \(Int(s.settings.radiusKm)) km of \($0)" } ?? "Home area not set",
                      systemImage: "mappin.and.ellipse")
                Label("\(count(s.feeds.filter { $0.type == .chat }.count, "chat")), \(count(s.feeds.filter { $0.type != .chat }.count, "group or website", "groups and websites")), \(count(s.instagram.count, "Instagram account"))",
                      systemImage: "person.3")
                HStack {
                    Label(model.calendarAllowed ? "Rides you're going to go in your RollCall calendar" : "Calendar not connected yet",
                          systemImage: "calendar")
                    if !model.calendarAllowed {
                        Button("Connect calendar…") { model.go(.calendar) }
                    }
                }
            }
            Toggle("Open RollCall when you log in", isOn: Binding(
                get: { model.app.opensAtLogin }, set: { model.app.setOpensAtLogin($0); model.objectWillChange.send() }))
            HStack {
                switch model.notificationsAllowed {
                case .some(true):
                    Label("Notifications are on: RollCall tells you when a chat plans a ride", systemImage: "bell.fill").foregroundStyle(.primary)
                case .some(false):
                    Text("Notifications are off, so RollCall can't tell you about plans in your chats.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Open Settings…") { model.openNotificationSettings() }
                case .none:
                    Button("Allow notifications") { model.allowNotifications() }
                    Text("so RollCall can tell you when a chat plans a ride").foregroundStyle(.secondary)
                }
            }
            Text("You can run this setup again any time from the menu bar: Set up RollCall…")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Beeper guide

/// Big, plain steps for setting up Beeper, each with a check RollCall does itself.
struct BeeperGuide: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        let step = model.guide ?? .download
        VStack(alignment: .leading, spacing: 16) {
            if step != .done {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Setting up Beeper · Step \(step.rawValue + 1) of \(SetupModel.GuideStep.counted)")
                        .font(.callout).foregroundStyle(.secondary)
                    ProgressView(value: Double(step.rawValue + 1), total: Double(SetupModel.GuideStep.counted))
                        .tint(.primary)
                }
            }
            switch step {
            case .download: download
            case .open: openApp
            case .accounts: accounts
            case .api: api
            case .connect: connect
            case .done: done
            }
        }
    }

    var download: some View {
        GuidePage(title: "Download Beeper",
                  intro: "Beeper is a free app that puts WhatsApp, Messenger and your other chats in one place on your Mac.",
                  steps: ["Click **Download Beeper** below. Beeper's website opens in your browser.",
                          "Click the **Download** button for Mac.",
                          "When it has downloaded, click **Open Downloads folder** below and double-click the Beeper file.",
                          "If a window shows Beeper and an Applications folder, drag Beeper onto Applications."]) {
            HStack {
                Button("Download Beeper") { model.app.open(SetupModel.beeperDownload) }.buttonStyle(.borderedProminent)
                Button("Open Downloads") { model.openDownloads() }
            }
            Status(done: model.beeperInstalled, waiting: "Waiting for Beeper to be installed…", finished: "Beeper is installed")
        }
    }

    var openApp: some View {
        GuidePage(title: "Open Beeper and make an account",
                  intro: "Beeper needs a free account. You only do this once.",
                  steps: ["Click **Open Beeper** below.",
                          "If your Mac asks whether you're sure you want to open it, click **Open**.",
                          "Choose to sign up, and type your email address.",
                          "Beeper emails you a code. Type it into Beeper to finish signing up.",
                          "Come back here and click **Next**."]) {
            Button("Open Beeper") { model.openBeeper() }.buttonStyle(.borderedProminent)
            Status(done: model.beeperOpen, waiting: "Waiting for Beeper to open…", finished: "Beeper is open")
        }
    }

    var accounts: some View {
        GuidePage(title: "Add your chats to Beeper",
                  intro: "Add the chat apps your riding groups use. You can add more later.",
                  steps: []) {
            VStack(alignment: .leading, spacing: 12) {
                Card {
                    Label("Open Beeper's settings", systemImage: "gearshape").font(.headline)
                    HStack(spacing: 6) {
                        Text("Click **Show Beeper**, then press")
                        KeyCap("⌘"); Text("and"); KeyCap(","); Text("together.")
                    }
                    Text("Click **Accounts** in the list on the left, then the **+** button to add one.")
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Show Beeper") { model.bringBeeperForward() }
                }
                Card {
                    Label("WhatsApp", systemImage: "phone.bubble").font(.headline)
                    NumberedSteps(["Choose **WhatsApp**. Beeper shows a square code.",
                                   "On your phone, open WhatsApp, then **Settings** → **Linked Devices** → **Link a Device**.",
                                   "Point your phone's camera at the code on your Mac screen."])
                }
                Card {
                    Label("Messenger", systemImage: "message").font(.headline)
                    NumberedSteps(["Choose **Messenger** and sign in with your Facebook account."])
                }
                Text("Chats can take a few minutes to appear in Beeper. You can click **Next** while they load.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var api: some View {
        GuidePage(title: "Switch on the connection for RollCall",
                  intro: "Beeper keeps other apps out until you switch this on. It only works on this Mac.",
                  steps: []) {
            Card {
                NumberedSteps(["Click **Show Beeper** below.",
                               "Press **⌘** and **,** together to open Beeper's settings.",
                               "In the list on the left, click **Developers**. You may need to scroll down to see it.",
                               "Switch on **Beeper Desktop API**."])
                Button("Show Beeper") { model.bringBeeperForward() }.buttonStyle(.borderedProminent)
            }
            Status(done: model.apiOn, waiting: "Waiting for the switch to be turned on…", finished: "It's on")
            DisclosureGroup("Can't find Developers?") {
                Text("Make sure Beeper is up to date: in the menu bar at the top of the screen, click **Beeper** → **Check for Updates**, then try again.")
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
            }
            .font(.callout)
        }
    }

    var connect: some View {
        GuidePage(title: "Let RollCall read your ride chats",
                  intro: "RollCall asks Beeper for permission to read. It can never send, change or delete messages, and nothing leaves your Mac.",
                  steps: ["Click **Connect RollCall** below.",
                          "A Beeper page opens in your browser. Then switch to Beeper and click **Allow**.",
                          "Back in RollCall, tick the group chats where people post rides, and click **Check these chats**."]) {
            Button("Connect RollCall") { model.connectFromGuide() }.buttonStyle(.borderedProminent)
            Status(done: Keychain.read() != nil && model.watchingChats > 0,
                   waiting: "Waiting for you to connect and choose chats…", finished: "Connected")
        }
    }

    var done: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 54))
            Text("Beeper is set up").font(.title.bold())
            Text("RollCall is checking \(model.watchingChats) chat\(model.watchingChats == 1 ? "" : "s"). When someone plans a ride, RollCall sums it up and asks you to check it.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Keep Beeper open (it can sit in the background) so RollCall can check your chats.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A step's title, a line of explanation, numbered instructions, then the step's own buttons and checks.
struct GuidePage<Extra: View>: View {
    var title: String
    var intro: String
    var steps: [String]
    @ViewBuilder var extra: Extra

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.title.bold())
            Text(intro).font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !steps.isEmpty { NumberedSteps(steps).font(.title3) }
            extra
        }
    }
}

struct NumberedSteps: View {
    var steps: [String]
    init(_ steps: [String]) { self.steps = steps }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(i + 1)").bold().frame(width: 22, height: 22)
                        .background(Circle().stroke(Color.primary, lineWidth: 1.5))
                    Text(.init(s)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// A key on the keyboard, drawn like the real thing.
struct KeyCap: View {
    var key: String
    init(_ key: String) { self.key = key }
    var body: some View {
        Text(key).font(.system(.body, design: .rounded).bold())
            .frame(minWidth: 26, minHeight: 24)
            .padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.5)))
    }
}

/// What RollCall can see right now, so nobody has to guess whether a step worked.
struct Status: View {
    var done: Bool
    var waiting: String
    var finished: String
    var body: some View {
        HStack(spacing: 8) {
            if done {
                Image(systemName: "checkmark.circle.fill")
                Text(finished).bold()
            } else {
                ProgressView().controlSize(.small)
                Text(waiting).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }
}

struct GuideFooter: View {
    @ObservedObject var model: SetupModel
    var step: SetupModel.GuideStep

    var body: some View {
        HStack {
            Button(step == .done ? "Back" : "Leave Beeper setup") {
                if step == .done { model.guideBack() } else { model.leaveGuide() }
            }
            Spacer()
            if step != .done, step != .download { Button("Back") { model.guideBack() } }
            if step == .done {
                Button("Continue") { model.leaveGuide(); model.next() }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Next") { model.guideNext() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
