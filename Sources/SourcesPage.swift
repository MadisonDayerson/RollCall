import SwiftUI
import AppKit

// MARK: - Sources

struct SourcesPage: View {
    @ObservedObject var model: UIModel

    var body: some View {
        let groups = model.sourceGroups()
        let rows = groups.flatMap(\.rows)
        ListAndDetail(showingDetail: model.selectedSource != nil, back: "Sources", close: { model.selectedSource = nil }) {
            List(selection: $model.selectedSource) {
                ForEach(groups) { g in
                    DisclosureGroup(isExpanded: model.expanded(g.name)) {
                        ForEach(g.rows) { row in
                            SourceRowView(row: row).tag(row.id)
                                .contextMenu {
                                    if model.feed(row.id) != nil {
                                        Button("Check now") { Task { await model.app.checkFeed(row.id) } }
                                            .disabled(model.app.checking.contains(row.id) || model.app.refreshing)
                                    }
                                    if model.removable(row.id) {
                                        Button("Remove…") { model.later { model.app.removeSource(row.id) } }
                                    }
                                }
                        }
                    } label: {
                        SourceGroupHeader(group: g, model: model)
                    }
                }
            }
            // Delete removes the selected source, as in other Mac lists.
            .onDeleteCommand {
                if let id = model.selectedSource, model.removable(id) { model.later { model.app.removeSource(id) } }
            }
        } detail: {
            Group {
                if let id = model.selectedSource, let row = rows.first(where: { $0.id == id }) {
                    SourceDetail(row: row, model: model)
                } else {
                    EmptyState(text: "Choose a source to see its options.",
                               detail: "Use + in the toolbar to add a website, forum, calendar, Meetup group, Facebook event, Instagram account or chat.")
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
                    .background(Color.secondary.opacity(0.14), in: Capsule())

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

    func interval(_ feed: Feed) -> some View {
        Picker("Check for new rides", selection: Binding(
            get: { feed.interval },
            set: { model.setInterval($0, for: [id]) })) {
            ForEach(Feed.intervals, id: \.self) { m in
                Text(Feed.describe(m) + (m == Feed.defaultInterval(kind) ? " (usual)" : "")).tag(m)
            }
        }
    }

    var body: some View {
        if let feed = model.feed(id) {
            VStack(alignment: .leading, spacing: 12) {
                Text(status).foregroundStyle(.secondary)
                // Wraps onto another row in a narrow window rather than being cut off.
                Flow { buttons(feed) }

                // The label goes above the menu when there isn't room beside it, so the page never runs wider
                // than its column.
                ViewThatFits(in: .horizontal) {
                    interval(feed).fixedSize()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Check for new rides")
                        interval(feed).labelsHidden().fixedSize()
                    }
                }

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

                SourceEditor(id: id, feed: feed, model: model)
            }
        }
    }
}

/// A source's name and link. The name saves as you type; a new link is read when you press Return or Change.
/// Chats are picked in Beeper (Change chats…), and Facebook's calendar link is replaced on its own page.
struct SourceEditor: View {
    let id: String
    let feed: Feed
    @ObservedObject var model: UIModel
    @StateObject private var name = Box("")
    @StateObject private var link = Box("")
    @StateObject private var pending = Box<Task<Void, Never>?>(nil)

    var linkEditable: Bool { feed.type != .chat && id != FeedLinks.facebookCalendarID }
    var newLink: String { link.value.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        Grid(alignment: .leading, verticalSpacing: 8) {
            GridRow {
                Text("Name").foregroundStyle(.secondary)
                TextField("Name", text: $name.value).textFieldStyle(.roundedBorder).labelsHidden()
            }
            if linkEditable {
                GridRow {
                    Text("Link").foregroundStyle(.secondary)
                    HStack {
                        TextField("Link", text: $link.value, onCommit: changeLink).textFieldStyle(.roundedBorder).labelsHidden()
                        Button("Change", action: changeLink).disabled(newLink.isEmpty || newLink == feed.url)
                    }
                }
                Text("A new link is read straight away; rides from the old one go, except ones you're going to.")
                    .font(.caption).foregroundStyle(.secondary).gridCellColumns(2)
            }
        }
        .onAppear(perform: load)
        .onChange(of: id) { old, _ in
            // Picking another source reuses this view, so save the name typed for the last one first.
            pending.value?.cancel()
            saveName(old, name.value)
            load()
        }
        .onChange(of: feed.url) { _, url in link.value = url }
        .onChange(of: name.value) { _, n in
            pending.value?.cancel()
            let k = id
            pending.value = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 800_000_000)
                if !Task.isCancelled { saveName(k, n) }
            }
        }
        .onDisappear { pending.value?.cancel(); saveName(id, name.value) }
    }

    func load() {
        name.value = model.feed(id)?.name ?? ""
        link.value = model.feed(id)?.url ?? ""
    }

    /// An empty name isn't saved: the source keeps the one it had.
    func saveName(_ key: String, _ text: String) {
        let n = text.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, model.feed(key)?.name != n else { return }
        model.setFeed(key) { $0.name = n }
        model.objectWillChange.send()
    }

    func changeLink() {
        guard !newLink.isEmpty, newLink != feed.url else { return }
        model.app.changeLink(id, to: newLink)
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
            FacebookCalendarBox(app: model.app, connected: model.app.facebookCalendarConnected, later: model.later, pointToSources: false)
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
    /// Says it's on the Sources page too, except when it's shown there.
    var pointToSources = true
    @StateObject private var link = Box("")

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Facebook events").font(.headline)
            if connected {
                Label("Connected. Bike events you're Going or Interested in on Facebook come in by themselves, as Going or Maybe.",
                      systemImage: "checkmark.circle.fill")
                    .fixedSize(horizontal: false, vertical: true)
                // The field has its own line, so its hint is never cut short by the buttons.
                TextField("Facebook calendar link", text: $link.value, prompt: Text("Paste a new link to replace it"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(connect)
                HStack {
                    Button("Replace", action: connect).disabled(link.value.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Disconnect") { later { app.removeSource(FeedLinks.facebookCalendarID) } }
                }
                if pointToSources {
                    Text("It's also listed under Facebook on the Sources page.")
                        .font(.caption).foregroundStyle(.secondary)
                }
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
