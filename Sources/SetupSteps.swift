import SwiftUI
import AppKit

/// The setup window and its steps.
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
                        .keyboardShortcut(.defaultAction).brandFill()
                } else {
                    // Once a step is done, Continue is the only choice (no "Skip" for something already done).
                    if ![.welcome, .home].contains(model.step) && !model.stepDone {
                        Button("Skip") { model.next() }
                    }
                    Button(model.step == .welcome ? "Get started" : "Continue") { model.next() }
                        .keyboardShortcut(.defaultAction).brandFill()
                }
            }
            .padding(16)
            }
        }
        .frame(minWidth: 520, minHeight: 400)
    }
}

extension View {
    /// Setup's main buttons are black and white, like the logo: near-black, so their white text still reads
    /// in dark mode. Only the filled buttons get it; ordinary buttons keep the system's own text colour.
    func brandFill() -> some View { tint(Color(white: 0.12)) }
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
                Label(m, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
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
                        .buttonStyle(.borderedProminent).brandFill()
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
                       text: "Tell RollCall how your crew keeps in touch. Every calendar event then says which Discord and voice chat group to join and where to share locations, and every ride gets a tag so everyone's photos and videos end up together.")
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
