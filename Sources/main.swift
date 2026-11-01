import AppKit
import SwiftUI
import ServiceManagement
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate, UNUserNotificationCenterDelegate {
    let store = Store()
    let calendar = CalendarSync()
    let geocoder = Geocoder()
    var statusItem: NSStatusItem!
    var refreshing = false
    /// Sources being checked one at a time from the window.
    var checking: Set<String> = []
    lazy var ui = UIModel(app: self)
    var window: NSWindow?
    lazy var setup = SetupModel(app: self)
    var setupWindow: NSWindow?
    /// A newer RollCall on GitHub, once a check has found one.
    var availableUpdate: Updater.Release?
    var timers: [Timer] = []

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let url = Bundle.main.url(forResource: "MenuIcon", withExtension: "png"), let img = NSImage(contentsOf: url) {
            // The gothic "RC" from the logo, drawn at 2x.
            img.size = NSSize(width: img.size.width / 2, height: img.size.height / 2)
            img.isTemplate = true
            img.accessibilityDescription = "RollCall"
            statusItem.button?.image = img
            statusItem.button?.imagePosition = .imageLeading
        } else if let img = NSImage(systemSymbolName: "motorcycle", accessibilityDescription: "RollCall") {
            img.isTemplate = true
            statusItem.button?.image = img
            statusItem.button?.imagePosition = .imageLeading
        } else {
            statusItem.button?.title = "🏍"
        }
        if Bundle.main.bundleIdentifier != nil { UNUserNotificationCenter.current().delegate = self }
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        updateBadge()

        calendar.preferredSourceID = store.state.settings.calendarSourceID
        Task {
            // Before setup, the calendar step asks for access with an explanation first.
            if store.state.setupDone { _ = await calendar.requestAccess() } else { calendar.checkAccess() }
            await refresh()
        }
        if !store.state.setupDone && !CommandLine.arguments.contains("--snapshots") { showSetup() }
        if let i = CommandLine.arguments.firstIndex(of: "--window") {
            // `--window sources` opens straight to a page (handy for checking the window).
            let page = CommandLine.arguments.dropFirst(i + 1).first.flatMap(UIModel.Page.init(rawValue:))
            showWindow(page: page)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshots"), i + 1 < CommandLine.arguments.count {
            Task { await saveSnapshots(to: URL(fileURLWithPath: CommandLine.arguments[i + 1])) }
        }
        // Feeds every 3 hours; Facebook downloads every minute.
        timers.append(Timer.scheduledTimer(withTimeInterval: 3 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        })
        timers.append(Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scanDownloads() }
        })
        // New versions: shortly after opening, then daily.
        if !CommandLine.arguments.contains("--snapshots") {
            Task { try? await Task.sleep(nanoseconds: 20_000_000_000); await checkForUpdates(manual: false) }
        }
        timers.append(Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.checkForUpdates(manual: false) }
        })
    }

    // MARK: - Refreshing

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        NotificationCenter.default.post(name: Store.changed, object: nil)
        defer { refreshing = false; updateBadge(); NotificationCenter.default.post(name: Store.changed, object: nil) }
        let started = Date()
        var refreshed: Set<String> = []
        var changed: [String] = []
        for feed in store.state.feeds {
            changed += await readFeed(feed)
            // Only calendar feeds list every event each time, so only they can show a ride was dropped.
            if feed.type == .calendar, store.state.feedErrors[feed.id] == nil { refreshed.insert(feed.id) }
            updateBadge()
        }
        scanDownloads(save: false)
        store.prune(refreshedSources: refreshed, refreshStarted: started)
        store.state.lastRefresh = Date()
        store.save()
        await geocoder.fill(store)
        for id in changed where store.decision(id) == .attending { syncCalendar(id) }
        store.save()
    }

    /// Reads one source and keeps what it found. Returns the ids of rides that changed.
    func readFeed(_ feed: Feed) async -> [String] {
        do {
            let r = try await SourceReader.read(feed, store: store)
            var changed = store.merge(r.events, source: feed.id, sourceName: feed.name, groupURL: feed.groupURL)
            changed += store.merge(r.guessed, source: feed.id, sourceName: feed.name, groupURL: feed.groupURL, needsCheck: true)
            addRecentPosts(r.undated, feed: feed)
            await keepReviews(r.reviews, feed: feed)
            store.state.feedErrors[feed.id] = nil
            store.state.lastChecked[feed.id] = Date()
            return changed
        } catch {
            store.state.feedErrors[feed.id] = error.localizedDescription
            return []
        }
    }

    // MARK: - Plans to review

    /// Saves conversations that moved on, summarises them, and lets the user know about new ones.
    func keepReviews(_ found: [PlanReview], feed: Feed) async {
        for var r in found {
            let old = store.state.reviews[r.id]
            if let old {
                r.created = old.created
                r.rideID = old.rideID
                // Added stays added; a dismissed conversation comes back only because it moved on.
                r.status = old.status == .added ? .added : .open
            }
            r.summary = await PlanSummariser.summarise(r, chatName: feed.name)
            // The on-device model read it and found no plan: keep it out of the way.
            if !r.summary.isPlan { r.status = .dismissed }
            let wasShowing = old?.status == .open && old?.summary.isPlan == true
            store.state.reviews[r.id] = r
            if r.status == .open, !wasShowing || old?.summary.start != r.summary.start || old?.summary.place != r.summary.place {
                notify(r, chatName: feed.name)
            }
        }
    }

    func openReviews() -> [PlanReview] {
        store.state.reviews.values.filter { $0.status == .open }.sorted { $0.updated > $1.updated }
    }

    func notify(_ r: PlanReview, chatName: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = "Possible ride plan: " + r.summary.title
        content.subtitle = chatName
        content.body = [r.summary.when, r.summary.place].compactMap { $0 }.joined(separator: " · ")
        content.userInfo = ["review": r.id]
        center.add(UNNotificationRequest(identifier: r.id, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler done: @escaping () -> Void) {
        let id = response.notification.request.content.userInfo["review"] as? String
        let isUpdate = response.notification.request.content.userInfo["update"] != nil
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if isUpdate { self.updateMenu(); return }
                self.ui.selectedReview = id
                self.showWindow(page: .review)
            }
        }
        done()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound])
    }

    /// Turns a reviewed plan into a ride, after the user checks the details.
    func addRide(fromReview id: String) {
        guard var r = store.state.reviews[id] else { return }
        let s = r.summary
        var start = s.start ?? Dialogs.nextSundayMorning()
        if s.start != nil, !s.hasTime { start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: start) ?? start }
        let chatName = store.state.feeds.first { $0.id == r.feedID }?.name ?? "a chat"
        let link = Beeper.chatLink(chatID: r.chatID, messageID: r.keyMessage?.id)
        guard let ride = Dialogs.manualRide(
            prefill: .init(title: s.title, start: start, hours: 3, location: s.place ?? "", link: link),
            note: "From the conversation in \(chatName). Check the time and meeting place." + (s.hasTime ? "" : " No time was agreed, so 9am is filled in.")) else { return }
        let notes = ([s.summary] + r.lines.map { "\($0.sender.isEmpty ? "Someone" : $0.sender): \($0.text)" }).joined(separator: "\n")
        let item = ICSEvent(uid: "plan-" + stableHash(r.id), title: ride.title, start: ride.start,
                            end: ride.start.addingTimeInterval(ride.hours * 3600), allDay: false, location: ride.location,
                            notes: notes.count > 1500 ? String(notes.prefix(1500)) + "…" : notes,
                            url: ride.link.isEmpty ? nil : ride.link)
        store.merge([item], source: "manual", sourceName: "Chat: " + chatName, groupURL: nil)
        let rideID = Store.eventID(source: "manual", item: item)
        r.status = .added
        r.rideID = rideID
        store.state.reviews[id] = r
        store.save()
        Task { await geocoder.fill(store); store.save() }
        updateBadge()
        if Dialogs.confirm("Ride added", "Are you going to “\(ride.title)”?", ok: "Yes, add to calendar") {
            decide(rideID, .attending)
        }
    }

    func dismissReview(_ id: String) {
        store.state.reviews[id]?.status = .dismissed
        store.save()
        updateBadge()
    }

    /// "Check now" for a single source.
    func checkFeed(_ id: String) async {
        guard let feed = store.state.feeds.first(where: { $0.id == id }) else { return }
        checking.insert(id)
        store.save()
        let changed = await readFeed(feed)
        checking.remove(id)
        store.save()
        await geocoder.fill(store)
        for id in changed where store.decision(id) == .attending { syncCalendar(id) }
        store.save()
        updateBadge()
    }

    func addRecentPosts(_ posts: [PostItem], feed: Feed) {
        guard !posts.isEmpty else { return }
        let cutoff = Date().addingTimeInterval(-30 * 86400)
        var list = posts + (store.state.recentPosts[feed.id] ?? [])
        var seen = Set<String>()
        list = list.filter { seen.insert($0.id).inserted && ($0.published ?? Date()) > cutoff }
        store.state.recentPosts[feed.id] = Array(list.prefix(15))
    }

    /// Ride-related posts with no date found, newest first, that haven't been marked read.
    func postsToLookAt() -> [(feed: Feed, post: PostItem)] {
        let since = store.state.postsReadUntil ?? .distantPast
        return store.state.feeds.flatMap { f in
            (store.state.recentPosts[f.id] ?? []).map { (f, $0) }
        }
        .filter { ($0.post.published ?? Date()) > since }
        .sorted { ($0.post.published ?? .distantPast) > ($1.post.published ?? .distantPast) }
    }

    func scanDownloads(save: Bool = true) {
        guard store.state.settings.watchDownloads else { return }
        let scanStart = Date()
        let files = DownloadsWatcher.newFacebookFiles(since: store.state.lastDownloadsScan)
        store.state.lastDownloadsScan = scanStart
        guard !files.isEmpty else { if save { store.save() }; return }
        let added = importFiles(files, source: "facebook", sourceName: "Facebook")
        if save { store.save() }
        updateBadge()
        if added > 0 {
            notifyImported(added, from: "Facebook")
        }
    }

    @discardableResult
    func importFiles(_ files: [URL], source: String, sourceName: String) -> Int {
        var count = 0
        var changed: [String] = []
        for f in files {
            guard let text = try? String(contentsOf: f, encoding: .utf8) else { continue }
            let items = ICSParser.parse(text)
            count += items.count
            changed += store.merge(items, source: source, sourceName: sourceName, groupURL: nil)
        }
        for id in changed where store.decision(id) == .attending { syncCalendar(id) }
        Task { await geocoder.fill(store); store.save() }
        return count
    }

    func notifyImported(_ n: Int, from: String) {
        statusItem.button?.title = " +\(n)"
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.updateBadge() }
    }

    func updateBadge() {
        let undecided = store.upcoming().filter { store.decision($0.id) == .undecided }.count + openReviews().count
        let hasImage = statusItem.button?.image != nil
        let base = hasImage ? "" : "🏍"
        statusItem.button?.title = undecided > 0 ? "\(base) \(undecided)" : base
        statusItem.button?.toolTip = undecided > 0 ? "\(undecided) ride\(undecided == 1 ? "" : "s") or plan\(undecided == 1 ? "" : "s") to decide on" : "RollCall"
    }

    // MARK: - Decisions and calendar

    func decide(_ id: String, _ d: Decision) {
        store.state.decisions[id] = d
        syncCalendar(id)
        store.save()
        updateBadge()
        if d == .attending, let ride = store.state.events[id], ride.url != nil,
           ride.isFacebook || ride.url!.contains("meetup.com") {
            // Facebook and Meetup only count you in when you press Going there yourself.
            if Dialogs.confirm("Added to your calendar",
                               "“\(ride.title)” is in your RollCall calendar.\n\nTo tell the organiser you're coming, open the event page and press Going (Facebook) or Attend (Meetup).",
                               ok: "Open event page") {
                open(ride.url)
            }
        }
    }

    func syncCalendar(_ id: String) {
        let attending = store.decision(id) == .attending
        let existing = store.state.calendarItems[id]
        if attending, let ride = store.state.events[id] {
            guard calendar.authorised else {
                Dialogs.info("Calendar access needed",
                             "RollCall isn't allowed to add events to Calendar yet.\n\nOpen System Settings → Privacy & Security → Calendars, and switch on RollCall (choose Full Access). Then mark the ride Attending again.")
                return
            }
            do {
                store.state.calendarItems[id] = try calendar.upsert(ride, existingID: existing, crewCard: crewCard(ride))
            } catch {
                Dialogs.info("Couldn't add to Calendar", error.localizedDescription)
            }
        } else if let existing {
            calendar.remove(itemID: existing)
            store.state.calendarItems[id] = nil
        }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let rides = store.upcoming()
        let active = rides.filter { store.decision($0.id) != .skip }
        let skipped = rides.filter { store.decision($0.id) == .skip }
        let s = store.state.settings

        menu.addItem(header("Rides within \(Int(s.radiusKm)) km of \(s.homeName), next \(s.daysAhead) days"))
        if active.isEmpty {
            menu.addItem(disabled(refreshing ? "Checking sources…" : "No upcoming rides yet."))
        }
        var lastMonth = ""
        for ride in active {
            let month = Self.monthFmt.string(from: ride.start)
            if month != lastMonth, active.count > 6 {
                if !lastMonth.isEmpty { menu.addItem(.separator()) }
                lastMonth = month
            }
            menu.addItem(rideItem(ride))
        }
        if !skipped.isEmpty {
            let item = NSMenuItem(title: "Skipped (\(skipped.count))", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            sub.autoenablesItems = false
            skipped.forEach { sub.addItem(rideItem($0)) }
            item.submenu = sub
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(action("Open RollCall…", #selector(openWindowMenu), key: "o"))
        let toReview = openReviews().count + postsToLookAt().count
        if toReview > 0 { menu.addItem(action("To review (\(toReview))…", #selector(openPostsMenu))) }
        menu.addItem(action("Add…", #selector(openAddMenu), key: "n"))
        menu.addItem(action("Set up RollCall…", #selector(openSetupMenu)))
        if let u = availableUpdate {
            menu.addItem(.separator())
            menu.addItem(action("Update to RollCall \(u.version)…", #selector(updateMenu)))
        }
        menu.addItem(.separator())
        menu.addItem(action(refreshing ? "Refreshing…" : "Refresh now", #selector(refreshNow), enabled: !refreshing))
        if let last = store.state.lastRefresh {
            menu.addItem(disabled("Updated \(Self.relative.localizedString(for: last, relativeTo: Date()))"))
        }
        menu.addItem(action("Quit RollCall", #selector(quit), key: "q"))
    }

    func rideItem(_ ride: RideEvent) -> NSMenuItem {
        let d = store.decision(ride.id)
        let mark: String
        switch d {
        case .attending: mark = "✅"
        case .maybe: mark = "🤔"
        case .skip: mark = "✖︎"
        case .undecided: mark = ride.needsCheck == true ? "🔎" : "🆕"
        }
        let when = ride.allDay ? Self.dayFmt.string(from: ride.start) : Self.dayTimeFmt.string(from: ride.start)
        let item = NSMenuItem(title: "\(mark)  \(when)  ·  \(ride.title)", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        sub.autoenablesItems = false

        sub.addItem(header(ride.title))
        var whenLine = ride.allDay ? Self.longDayFmt.string(from: ride.start) : Self.longFmt.string(from: ride.start)
        if let end = ride.end, !ride.allDay { whenLine += " – " + Self.timeFmt.string(from: end) }
        sub.addItem(disabled("🗓  " + whenLine))
        if !ride.location.isEmpty {
            var place = "📍  " + ride.location
            if let km = ride.distanceKm { place += String(format: "  (%.0f km away)", km) }
            sub.addItem(disabled(place))
        }
        sub.addItem(disabled("ℹ️  From " + ride.sourceName))
        if ride.needsCheck == true {
            sub.addItem(disabled("⚠️  Date and place were read from the post. Check them before going."))
        }
        sub.addItem(.separator())

        for (label, choice) in [("Attending (add to calendar)", Decision.attending), ("Maybe", .maybe), ("Skip", .skip)] {
            let it = action(label, #selector(choose(_:)))
            it.representedObject = [ride.id, choice.rawValue]
            it.state = d == choice ? .on : .off
            sub.addItem(it)
        }
        if d != .undecided {
            let it = action("Undecided", #selector(choose(_:)))
            it.representedObject = [ride.id, Decision.undecided.rawValue]
            sub.addItem(it)
        }
        sub.addItem(.separator())
        if let url = ride.url {
            let it = action(ride.linkLabel, #selector(openLink(_:)))
            it.representedObject = url
            sub.addItem(it)
        }
        if let g = ride.groupURL {
            let it = action("Open group page (to join)", #selector(openLink(_:)))
            it.representedObject = g
            sub.addItem(it)
        } else if ride.isFacebook {
            let it = action("Add the Facebook group link…", #selector(setGroupLink(_:)))
            it.representedObject = ride.id
            sub.addItem(it)
        }
        if !ride.location.isEmpty {
            let it = action("Show meeting place in Maps", #selector(openMaps(_:)))
            it.representedObject = ride.location
            sub.addItem(it)
        }
        if Store.userAdded.contains(ride.source) || ride.needsCheck == true {
            let it = action("Remove this ride", #selector(removeRide(_:)))
            it.representedObject = ride.id
            sub.addItem(it)
        }
        item.submenu = sub
        return item
    }

    func header(_ title: String) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        it.attributedTitle = NSAttributedString(string: title, attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
        it.isEnabled = false
        return it
    }

    func disabled(_ title: String) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        it.isEnabled = false
        return it
    }

    func action(_ title: String, _ sel: Selector, key: String = "", enabled: Bool = true) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        it.target = self
        it.isEnabled = enabled
        return it
    }

    // MARK: - Menu actions

    @objc func choose(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2,
              let d = Decision(rawValue: pair[1]) else { return }
        decide(pair[0], d)
    }

    @objc func openLink(_ sender: NSMenuItem) { open(sender.representedObject as? String) }

    func open(_ link: String?) {
        if let link, link.hasPrefix(Beeper.chatLinkPrefix) {
            Task {
                do { try await Beeper.focus(link: link) } catch {
                    Dialogs.info("Couldn't open the chat in Beeper", error.localizedDescription)
                }
            }
            return
        }
        guard let link, let url = URL(string: link) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc func openMaps(_ sender: NSMenuItem) { openMaps(place: sender.representedObject as? String) }

    func openMaps(place: String?) {
        guard let place, let q = place.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }
        open("maps://?q=\(q)")
    }

    // MARK: - Window

    @objc func openWindowMenu() { showWindow() }
    @objc func openPostsMenu() { showWindow(page: .review) }
    @objc func openAddMenu() { showWindow(page: .sources, add: true) }

    func showWindow(page: UIModel.Page? = nil, add: Bool = false) {
        if let page { ui.page = page }
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 640),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "RollCall"
            w.contentViewController = NSHostingController(rootView: MainView(model: ui))
            w.setContentSize(NSSize(width: 980, height: 640))
            w.minSize = NSSize(width: 760, height: 480)
            w.isReleasedWhenClosed = false
            w.setFrameAutosaveName("RollCallWindow")
            w.delegate = self
            if !w.setFrameUsingName("RollCallWindow") { w.center() }
            window = w
        }
        // Show in the Dock and ⌘-Tab while the window is open.
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if add { ui.showAdd = true }
    }

    /// For checking the design: saves a picture of each page of the window.
    func saveSnapshots(to folder: URL) async {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func snap(_ name: String, _ w: NSWindow?) async {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            // An app may capture its own windows; this includes the sidebar's translucency.
            guard let w, let img = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(w.windowNumber),
                                                           [.boundsIgnoreFraming, .bestResolution]) else { return }
            try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?
                .write(to: folder.appendingPathComponent(name + ".png"))
        }
        showWindow(page: .rides)
        if ui.rides().isEmpty { ui.rideFilter = .skipped }
        ui.selectedRide = ui.rides().first?.id
        await snap("1-rides", window)
        ui.page = .review
        // Show a sample plan if there's nothing real to review (never saved: it's removed straight after).
        while refreshing { try? await Task.sleep(nanoseconds: 500_000_000) }
        let demo = store.state.reviews.values.contains { $0.status == .open } ? nil : demoReview()
        if let demo { store.state.reviews[demo.id] = demo; ui.objectWillChange.send() }
        await snap("2-review", window)
        if let demo { store.state.reviews[demo.id] = nil; ui.objectWillChange.send() }
        ui.page = .sources
        ui.selectedSource = store.state.feeds.first(where: { $0.type == .forum })?.id
        await snap("3-sources-forum", window)
        ui.selectedSource = store.state.feeds.first(where: { $0.type == .chat })?.id
        await snap("4-sources-chat", window)
        ui.selectedSource = store.state.instagram.first.map { "instagram:" + $0.handle }
        await snap("5-sources-instagram", window)
        ui.selectedSource = "yours"
        await snap("6-sources-yours", window)
        ui.page = .settings
        await snap("7-settings", window)
        ui.showAdd = true
        try? await Task.sleep(nanoseconds: 800_000_000)
        await snap("8-add", window?.attachedSheet)
        ui.showAdd = false
        window?.close()
        showSetup()
        for step in SetupModel.Step.allCases {
            setup.go(step)
            if step == .messages { await setup.checkBeeper() }
            await snap("9-setup-\(step.rawValue)-\(step)", setupWindow)
        }
        setupWindow?.close()
    }

    func demoReview() -> PlanReview {
        let now = Date()
        let lines = [("Alex", "Thinking about going for a ride Saturday arvo. Anyone want to join?"),
                     ("Jordan", "Keen! Could meet at Shell Coldstream 2pm and do the Black Spur?"),
                     ("Alex", "Sounds good, see you there"),
                     ("Casey", "Might join if the weather holds")].enumerated().map { i, m in
            ChatLine(id: "demo\(i)", sender: m.0, sent: now.addingTimeInterval(Double(i - 4) * 300), text: m.1,
                     mentionsWhen: PlanFinder.mentionsWhen(m.1))
        }
        let saturday = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 14, weekday: 7), matchingPolicy: .nextTime)
        let summary = PlanSummary(title: "Saturday Black Spur ride", when: "Saturday afternoon, 2pm", start: saturday, hasTime: true,
                                  place: "Shell Coldstream", who: ["Alex", "Jordan"], undecided: "Whether Casey is coming",
                                  summary: "Alex suggested a Saturday afternoon ride. Jordan proposed meeting at Shell Coldstream at 2pm and riding the Black Spur, and Alex agreed.",
                                  isPlan: true, byAI: true)
        return PlanReview(id: "plan:demo", feedID: store.state.feeds.first { $0.type == .chat }?.id ?? "", chatID: "demo",
                          lines: lines, summary: summary, status: .open, created: now, updated: now)
    }

    /// Clicking the Dock icon brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func windowWillClose(_ notification: Notification) {
        let closing = notification.object as? NSWindow
        if closing === setupWindow, !store.state.setupDone, !CommandLine.arguments.contains("--snapshots") {
            // Closing the wizard counts as skipping it; the menu can open it again.
            store.state.setupDone = true
            store.save()
        }
        let stillOpen = [window, setupWindow].contains { $0 != nil && $0 !== closing && $0!.isVisible }
        if !stillOpen { NSApp.setActivationPolicy(.accessory) }
    }

    // MARK: - Riding together

    func links(_ ride: RideEvent) -> CrewLinks? { store.state.crew[Crew.key(forSource: ride.source)] }
    func rideTag(_ ride: RideEvent) -> String { Crew.rideTag(ride, override: store.state.rideTags[ride.id]) }
    func crewCard(_ ride: RideEvent) -> [String] {
        Crew.card(ride, together: store.state.settings.crew, links: links(ride), override: store.state.rideTags[ride.id])
    }
    func invite(_ ride: RideEvent) -> String {
        Crew.invite(ride, when: rideWhen(ride, long: true), together: store.state.settings.crew,
                    links: links(ride), override: store.state.rideTags[ride.id])
    }
    func caption(_ ride: RideEvent) -> String {
        Crew.caption(ride, together: store.state.settings.crew, links: links(ride), override: store.state.rideTags[ride.id])
    }

    func setTogether(_ t: Together) {
        guard t != store.state.settings.crew else { return }
        store.state.settings.together = t
        resyncCalendar()
        store.save()
    }

    func setCrewLinks(_ key: String, _ l: CrewLinks) {
        let clean = CrewLinks(discord: l.discord?.trimmingCharacters(in: .whitespaces).nilIfEmpty,
                              tags: l.tags?.trimmingCharacters(in: .whitespaces).nilIfEmpty)
        guard clean != store.state.crew[key] ?? CrewLinks() else { return }
        store.state.crew[key] = clean == CrewLinks() ? nil : clean
        resyncCalendar()
        store.save()
    }

    func setRideTag(_ id: String, _ tag: String) {
        let t = tag.trimmingCharacters(in: .whitespaces)
        store.state.rideTags[id] = t.isEmpty ? nil : t
        syncCalendar(id)
        store.save()
    }

    /// Rewrites the crew details on calendar events for rides you're going to.
    func resyncCalendar() {
        guard calendar.authorised else { return }
        for (id, d) in store.state.decisions where d == .attending && store.state.calendarItems[id] != nil { syncCalendar(id) }
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Opens the share menu (Messages, AirDrop, Mail…) next to the pointer.
    func share(_ items: [Any]) {
        guard let view = NSApp.keyWindow?.contentView else { return }
        let p = view.convert(view.window!.mouseLocationOutsideOfEventStream, from: nil)
        NSSharingServicePicker(items: items).show(relativeTo: NSRect(x: p.x, y: p.y, width: 1, height: 1), of: view, preferredEdge: .minY)
    }

    /// Shares the invite text with a calendar file friends can add in one tap.
    func shareInvite(_ ride: RideEvent) {
        let text = invite(ride)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(
            ride.title.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.prefix(5).joined(separator: " ") + ".ics")
        try? Crew.ics(ride, description: text).write(to: file, atomically: true, encoding: .utf8)
        share([text, file])
    }

    /// Picks photos or videos from the ride and shares them with the caption (also copied, for apps that drop text).
    func shareFootage(_ ride: RideEvent) {
        Dialogs.bringForward()
        let panel = NSOpenPanel()
        panel.title = "Choose photos or videos from the ride"
        panel.allowedContentTypes = [.image, .movie]
        panel.allowsMultipleSelection = true
        panel.directoryURL = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let text = caption(ride)
        copy(text)
        share([text] + panel.urls)
    }

    func openFindMy() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.findmy") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    // MARK: - Updates

    @objc func updateMenu() { if let u = availableUpdate { offerUpdate(u) } }

    /// Looks on GitHub for a newer version. A manual check always says what it found.
    func checkForUpdates(manual: Bool) async {
        guard manual || store.state.settings.checkForUpdates ?? true else { return }
        let found: Updater.Release?
        do {
            found = try await Updater.latest()
        } catch {
            if manual { Dialogs.info("Couldn't check for updates", error.localizedDescription) }
            return
        }
        guard let r = found, Updater.isNewer(r.version, than: Updater.currentVersion) else {
            availableUpdate = nil
            if manual { Dialogs.info("RollCall is up to date", "You have the latest version (\(Updater.currentVersion)).") }
            return
        }
        let isNew = availableUpdate?.version != r.version
        availableUpdate = r
        if manual {
            offerUpdate(r)
        } else if isNew, r.version != store.state.settings.skippedVersion {
            notifyUpdate(r)
        }
    }

    func notifyUpdate(_ r: Updater.Release) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = "RollCall \(r.version) is available"
        content.body = "Choose Update in the RollCall menu to install it."
        content.userInfo = ["update": r.version]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "update-\(r.version)", content: content, trigger: nil))
    }

    func offerUpdate(_ r: Updater.Release) {
        Dialogs.bringForward()
        let a = NSAlert()
        a.messageText = "RollCall \(r.version) is available"
        let notes = r.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        a.informativeText = "You have version \(Updater.currentVersion)." + (notes.isEmpty ? "" : "\n\nWhat's new:\n" + notes)
            + "\n\nRollCall downloads the update, replaces itself and reopens. Your rides and settings stay as they are."
        a.addButton(withTitle: "Update now")
        a.addButton(withTitle: "Later")
        a.addButton(withTitle: "Skip this version")
        switch a.runModal() {
        case .alertFirstButtonReturn:
            Task {
                do { try await Updater.install(r) } catch {
                    if Dialogs.confirm("Couldn't install the update",
                                       "\(error.localizedDescription)\n\nYou can download it from GitHub instead: open the .dmg and drag RollCall into Applications, replacing the old one.",
                                       ok: "Open download page") {
                        open(r.page)
                    }
                }
            }
        case .alertThirdButtonReturn:
            store.state.settings.skippedVersion = r.version
            availableUpdate = nil
            store.save()
        default:
            break
        }
    }

    // MARK: - Setup

    @objc func openSetupMenu() { showSetup() }

    func showSetup() {
        if setupWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 620),
                             styleMask: [.titled, .closable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.title = "Set up RollCall"
            w.contentViewController = NSHostingController(rootView: SetupView(model: setup))
            w.setContentSize(NSSize(width: 660, height: 620))
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            setupWindow = w
        }
        setup.go(.welcome)
        NSApp.setActivationPolicy(.regular)
        setupWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func finishSetup(openWindow: Bool) {
        store.state.setupDone = true
        store.save()
        setupWindow?.close()
        if openWindow { showWindow(page: .rides) }
        Task { await refresh() }
    }

    // MARK: - Adding

    /// The one way in: works out what a pasted link is and adds it the right way.
    func add(link raw: String) {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
        let lower = s.lowercased()
        if Store.facebookEventID(s) != nil || lower.contains("fb.me/e/") {
            addFacebookEvent(link: s)
        } else if lower.contains("facebook.com") {
            Dialogs.info("Facebook groups and pages can't be added",
                         "Facebook doesn't let apps read groups or pages. Add each Facebook event instead: open the event, click Share → Copy link, and paste that link.")
        } else if lower.contains("instagram.com/p/") || lower.contains("instagram.com/reel") {
            addFromPost(link: s)
        } else if lower.contains("instagram.com") || (s.hasPrefix("@") && Self.instagramHandle(s) != nil) {
            if let handle = Self.instagramHandle(s) { addInstagramHandle(handle) }
        } else {
            addFeed(link: s)
        }
    }

    func addFacebookEvent(link: String = "") {
        guard let vals = Dialogs.ask(
            "Add a Facebook event",
            "Paste the link to the Facebook event. If it belongs to a group you want to join, paste the group's link too (optional).",
            fields: [("Event link", "https://www.facebook.com/events/1234567890"),
                     ("Group link (optional)", "https://www.facebook.com/groups/…")],
            values: [link]),
              !vals[0].isEmpty else { return }
        guard let fbID = Store.facebookEventID(vals[0]) else {
            Dialogs.info("That doesn't look like a Facebook event link",
                         "It should look like https://www.facebook.com/events/1234567890. On the event page, use Share → Copy link.")
            return
        }
        let eventURL = "https://www.facebook.com/events/\(fbID)/"
        if !vals[1].isEmpty {
            store.state.facebookGroups[fbID] = vals[1]
            if var e = store.state.events["facebook:\(fbID)"] { e.groupURL = vals[1]; store.state.events[e.id] = e }
        }
        store.save()

        Dialogs.bringForward()
        let a = NSAlert()
        a.messageText = "Get the event's details"
        a.informativeText = """
        RollCall can't read Facebook for you, so the event page will open in your browser. Then:

        1. Under the event title, click the ⋯ (More) button.
        2. Choose “Add to calendar”, then “Download” or “Export event”.

        RollCall picks up the downloaded file by itself within a minute.

        If you don't see that option, choose “Type details instead”.
        """
        a.addButton(withTitle: "Open event page")
        a.addButton(withTitle: "Type details instead")
        a.addButton(withTitle: "Cancel")
        switch a.runModal() {
        case .alertFirstButtonReturn:
            if !store.state.settings.watchDownloads {
                store.state.settings.watchDownloads = true
                store.save()
            }
            open(eventURL)
        case .alertSecondButtonReturn:
            addManual(prefill: eventURL)
        default: break
        }
    }

    func addManual(prefill: String = "") {
        guard let r = Dialogs.manualRide(prefillLink: prefill) else { return }
        var link: String? = r.link.isEmpty ? nil : r.link
        if let l = link, !l.lowercased().hasPrefix("http") { link = "https://" + l }
        let fbID = link.flatMap(Store.facebookEventID)
        let item = ICSEvent(uid: fbID.map { "e\($0)@facebook.com" } ?? "manual-\(UUID().uuidString)",
                            title: r.title, start: r.start, end: r.start.addingTimeInterval(r.hours * 3600),
                            allDay: false, location: r.location, notes: "", url: link)
        let source = fbID != nil ? "facebook" : "manual"
        store.merge([item], source: source, sourceName: fbID != nil ? "Facebook" : "Added by hand", groupURL: nil)
        let id = Store.eventID(source: source, item: item)
        store.save()
        Task { await geocoder.fill(store); store.save() }
        updateBadge()
        if Dialogs.confirm("Ride added", "Are you going to “\(r.title)”?", ok: "Yes, add to calendar") {
            decide(id, .attending)
        }
    }

    func importICS() {
        let files = Dialogs.chooseICSFiles()
        guard !files.isEmpty else { return }
        let isFB = files.contains { (try? String(contentsOf: $0, encoding: .utf8))?.contains("facebook.com") ?? false }
        let n = importFiles(files, source: isFB ? "facebook" : "file", sourceName: isFB ? "Facebook" : "Imported file")
        store.save()
        updateBadge()
        Dialogs.info("Imported \(n) event\(n == 1 ? "" : "s")", "They're on the Rides page, where you can choose Attending, Maybe or Skip.")
    }

    func addFeed(link raw: String) {
        Task {
            do {
                let feed = try await Web.discover(raw)
                if let existing = store.state.feeds.first(where: { $0.id == feed.id || $0.url == feed.url }) {
                    Dialogs.info("Already added", "\(existing.name) is already one of your sources.")
                    return
                }
                store.state.feeds.append(feed)
                ui.selectedSource = feed.id
                await checkFeed(feed.id)
                let r = store.upcoming().filter { $0.source == feed.id }.count
                let undated = (store.state.recentPosts[feed.id] ?? []).count
                var msg = "Found \(r) upcoming ride\(r == 1 ? "" : "s") nearby."
                if undated > 0 { msg += " \(undated) post\(undated == 1 ? "" : "s") without a date are under Posts to look at." }
                if feed.type == .forum || feed.type == .posts { msg += "\n\nNew posts are checked every few hours. Rides marked 🔎 had their date read from the post text, so check it before going." }
                Dialogs.info("Added \(feed.name)", msg)
            } catch FeedError.privateFeed where raw.contains("meetup.com") {
                Dialogs.info("This Meetup group's calendar is private",
                             """
                             You'll need your personal link for it:

                             1. Join the group on Meetup (RollCall can open the page for you).
                             2. On the group's Events tab, click the ⋯ menu or the calendar icon and choose “Subscribe” / “Add to calendar”.
                             3. Copy the link it gives you (it starts with webcal:// or https://), then click + and paste it.
                             """)
                open(FeedLinks.normalise(raw)?.groupURL)
            } catch {
                Dialogs.info("Couldn't use that link", error.localizedDescription
                             + "\n\nIf the site only posts rides as news or photos, use “Paste a post or message” for each one.")
            }
        }
    }

    func addFromPost(link: String = "") {
        guard let post = Dialogs.pastedPost(link: link), !(post.text.isEmpty && post.link.isEmpty) else { return }
        var link = post.link
        if !link.isEmpty, !link.lowercased().hasPrefix("http") { link = "https://" + link }
        let found = TextDetect.scan(post.text, daysAhead: 365)
        var start = found.start ?? Dialogs.nextSundayMorning()
        if found.start != nil, !found.hasTime {
            start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: start) ?? start
        }
        var notes: [String] = []
        notes.append(found.start == nil ? "No date found in the text, so pick one below."
                     : found.hasTime ? "Date and time found in the text. Check they're right."
                     : "A date was found but no time, so 9am is filled in. Check it.")
        if found.address == nil { notes.append("No address found. Type the meeting place if you know it.") }
        guard let r = Dialogs.manualRide(
            prefill: .init(title: TextDetect.title(from: post.text), start: start, hours: 4,
                           location: found.address ?? "", link: link),
            note: notes.joined(separator: " ")) else { return }

        var url: String? = r.link.isEmpty ? nil : r.link
        if let l = url, !l.lowercased().hasPrefix("http") { url = "https://" + l }
        let fbID = url.flatMap(Store.facebookEventID)
        let isInstagram = url?.contains("instagram.com") ?? false
        let source = fbID != nil ? "facebook" : isInstagram ? "instagram" : "manual"
        let item = ICSEvent(uid: fbID.map { "e\($0)@facebook.com" } ?? "post-\(UUID().uuidString)",
                            title: r.title, start: r.start, end: r.start.addingTimeInterval(r.hours * 3600),
                            allDay: false, location: r.location,
                            notes: post.text.count > 1000 ? String(post.text.prefix(1000)) + "…" : post.text, url: url)
        let name = fbID != nil ? "Facebook" : isInstagram ? "Instagram post" : "Added from a post"
        store.merge([item], source: source, sourceName: name, groupURL: nil)
        let id = Store.eventID(source: source, item: item)
        store.save()
        Task { await geocoder.fill(store); store.save() }
        updateBadge()
        if Dialogs.confirm("Ride added", "Are you going to “\(r.title)”?", ok: "Yes, add to calendar") {
            decide(id, .attending)
        }
    }

    static func instagramHandle(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = s.range(of: #"instagram\.com/([A-Za-z0-9._]+)"#, options: .regularExpression) {
            s = String(s[r]).replacingOccurrences(of: "instagram.com/", with: "")
            if ["p", "reel", "reels", "stories", "explore"].contains(s) { return nil }
        }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "@/ "))
        return s.range(of: #"^[A-Za-z0-9._]{1,30}$"#, options: .regularExpression) != nil ? s.lowercased() : nil
    }

    func addInstagramHandle(_ handle: String) {
        guard !store.state.instagram.contains(where: { $0.handle == handle }) else {
            Dialogs.info("Already added", "@\(handle) is already one of your sources.")
            return
        }
        store.state.instagram.append(InstagramAccount(handle: handle))
        ui.selectedSource = "instagram:" + handle
        store.save()
    }

    func openInstagram(_ h: String) {
        open("https://www.instagram.com/\(h)/")
        if let i = store.state.instagram.firstIndex(where: { $0.handle == h }) {
            store.state.instagram[i].lastOpened = Date()
        }
        store.save()
    }

    // MARK: Beeper chats

    func setUpBeeper() async {
        guard await Beeper.isRunning() else {
            Dialogs.info("Open Beeper first",
                         "RollCall reads chats through Beeper Desktop, so Beeper needs to be open with its Desktop API switched on:\n\n1. Open Beeper Desktop.\n2. Open Settings (⌘,) → Developers.\n3. Switch on Beeper Desktop API.\n\nThen try again.")
            return
        }
        var chats: [Beeper.Chat]
        do {
            chats = try await Beeper.chats()
        } catch Beeper.BeeperError.notConnected {
            guard Dialogs.confirm("Connect RollCall to Beeper",
                                  "A Beeper page opens in your browser, then Beeper itself asks whether RollCall may read your chats. Switch to Beeper and click Allow (or Approve).\n\nRollCall only asks to read, so it can't send, edit or delete anything. Messages stay on your Mac.",
                                  ok: "Open Beeper's page") else { return }
            do {
                try await Beeper.connect { NSWorkspace.shared.open($0) }
                chats = try await Beeper.chats()
            } catch {
                Dialogs.info("Couldn't connect to Beeper", error.localizedDescription)
                return
            }
        } catch {
            Dialogs.info("Couldn't read your Beeper chats", error.localizedDescription)
            return
        }
        chats = chats.filter { $0.isArchived != true }
        // Ride chats are nearly always groups; list those first.
        chats = chats.filter { $0.type != "single" } + chats.filter { $0.type == "single" }
        guard !chats.isEmpty else {
            Dialogs.info("No chats found", "Beeper didn't list any chats. Check that WhatsApp (or another network) is connected in Beeper → Settings → Accounts.")
            return
        }
        let watchedFeeds = store.state.feeds.filter { $0.type == .chat }
        let watched = Set(watchedFeeds.map { Beeper.chatID(of: $0) })
        guard let picked = Dialogs.pickChats(chats, watched: watched) else { return }

        for f in watchedFeeds where !picked.contains(Beeper.chatID(of: f)) {
            forgetFeed(f.id)
        }
        var added: [Feed] = []
        for c in chats where picked.contains(c.id) && !watched.contains(c.id) {
            let f = Beeper.feed(for: c)
            store.state.feeds.append(f)
            added.append(f)
        }
        store.save()
        for f in added { await checkFeed(f.id) }
        if let f = added.first { ui.selectedSource = f.id }
    }

    // MARK: - Removing

    /// The one way out, for anything on the Sources page.
    func removeSource(_ id: String) {
        if id.hasPrefix("instagram:") {
            let h = String(id.dropFirst("instagram:".count))
            guard Dialogs.confirm("Remove @\(h)?", "It won't be on your list of accounts to check any more.", ok: "Remove") else { return }
            store.state.instagram.removeAll { $0.handle == h }
        } else if let feed = store.state.feeds.first(where: { $0.id == id }) {
            guard Dialogs.confirm("Remove \(feed.name)?",
                                  "Its rides will disappear from the list. Rides you marked Attending stay in your calendar.",
                                  ok: "Remove") else { return }
            forgetFeed(id)
        } else {
            return
        }
        if ui.selectedSource == id { ui.selectedSource = nil }
        store.save()
        updateBadge()
    }

    func forgetFeed(_ id: String) {
        store.state.feeds.removeAll { $0.id == id }
        store.state.feedErrors[id] = nil
        store.state.recentPosts[id] = nil
        store.state.lastChecked[id] = nil
        for (eid, e) in store.state.events where e.source == id && store.decision(eid) != .attending {
            store.state.events[eid] = nil
        }
    }

    @objc func removeRide(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        removeRide(id: id)
    }

    func removeRide(id: String) {
        store.state.decisions[id] = .skip
        syncCalendar(id)
        store.state.events[id] = nil
        store.state.decisions[id] = nil
        store.save()
        updateBadge()
    }

    @objc func setGroupLink(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        setGroupLink(rideID: id)
    }

    func setGroupLink(rideID id: String) {
        guard let vals = Dialogs.ask("Facebook group link", "Paste the link to the group that runs this ride.",
                                     fields: [("", "https://www.facebook.com/groups/…")], ok: "Save"),
              !vals[0].isEmpty, var e = store.state.events[id] else { return }
        e.groupURL = vals[0]
        store.state.events[id] = e
        if let fb = Store.facebookEventID(e.url ?? "") { store.state.facebookGroups[fb] = vals[0] }
        store.save()
    }

    func markPostsRead() {
        store.state.postsReadUntil = Date()
        store.save()
    }

    @objc func refreshNow() { Task { await refresh() } }

    func openCalendarApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    // MARK: - Settings

    /// Returns an error message to show, or nil when saved.
    /// `force` looks the place up even when the name hasn't changed (setup uses it to learn the city and state).
    func setHomeArea(place: String, km: Double, days: Int, force: Bool = false) async -> String? {
        if km > 0 { store.state.settings.radiusKm = km }
        if days > 0 { store.state.settings.daysAhead = days }
        let place = place.trimmingCharacters(in: .whitespaces)
        if !place.isEmpty, force || place != store.state.settings.homeName || store.state.settings.homeRegion == nil {
            guard let found = try? await CLGeocoderShim.find(place) else {
                store.save()
                return "Couldn't find “\(place)”. Try a suburb or town with its state, like Ringwood VIC or Newtown NSW."
            }
            store.state.settings.homeName = place
            store.state.settings.homeLatitude = found.latitude
            store.state.settings.homeLongitude = found.longitude
            store.state.settings.homeCity = found.city
            store.state.settings.homeRegion = found.region
            store.state.settings.homeCountry = found.country
            for (id, var e) in store.state.events {
                e.distanceKm = store.distance(e)
                store.state.events[id] = e
            }
        }
        store.save()
        updateBadge()
        return nil
    }

    func setWatchDownloads(_ on: Bool) {
        store.state.settings.watchDownloads = on
        if on { store.state.lastDownloadsScan = Date() }
        store.save()
    }

    var opensAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    func setOpensAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            Dialogs.info("Couldn't change the login setting",
                         "Add RollCall yourself in System Settings → General → Login Items.\n\n(\(error.localizedDescription))")
        }
        store.save()
    }

    @objc func quit() { NSApp.terminate(nil) }

    // MARK: - Formatting

    static let dayTimeFmt: DateFormatter = fmt("EEE d MMM, h:mma")
    static let dayFmt: DateFormatter = fmt("EEE d MMM")
    static let longFmt: DateFormatter = fmt("EEEE d MMMM, h:mm a")
    static let longDayFmt: DateFormatter = fmt("EEEE d MMMM '(all day)'")
    static let timeFmt: DateFormatter = fmt("h:mm a")
    static let monthFmt: DateFormatter = fmt("yyyy-MM")
    static let relative: RelativeDateTimeFormatter = {
        let r = RelativeDateTimeFormatter()
        r.unitsStyle = .full
        return r
    }()

    static func fmt(_ pattern: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_AU")
        f.dateFormat = pattern
        f.amSymbol = "am"
        f.pmSymbol = "pm"
        return f
    }
}

extension RideEvent {
    /// What the "open" button for this ride's link should say.
    var linkLabel: String {
        guard let url else { return "" }
        return isFacebook ? "Open on Facebook (to RSVP)"
            : url.contains("meetup.com") ? "Open on Meetup (to RSVP)"
            : url.contains("instagram.com") ? "Open the Instagram post"
            : url.hasPrefix(Beeper.chatLinkPrefix) ? "Open the message in Beeper"
            : needsCheck == true ? "Open the post" : "Open event page"
    }
}

import CoreLocation

enum CLGeocoderShim {
    @MainActor
    static func locate(_ place: String) async throws -> (Double, Double)? {
        guard let f = try await find(place) else { return nil }
        return (f.latitude, f.longitude)
    }

    struct Found { var latitude: Double; var longitude: Double; var city: String?; var region: String?; var country: String?; var label: String }

    /// Looks a place up, preferring matches in the Mac's own country (so "Ringwood" is the Victorian one here).
    @MainActor
    static func find(_ place: String) async throws -> Found? {
        let marks = try await CLGeocoder().geocodeAddressString(place)
        let here = Locale.current.region?.identifier
        guard let m = marks.first(where: { $0.isoCountryCode == here }) ?? marks.first,
              let c = m.location?.coordinate else { return nil }
        let label = [m.locality ?? m.name, m.administrativeArea, m.country].compactMap { $0 }.joined(separator: ", ")
        return Found(latitude: c.latitude, longitude: c.longitude, city: m.locality ?? m.subAdministrativeArea,
                     region: m.administrativeArea, country: m.country, label: label)
    }
}

// For tuning: `RollCall --check-chats` prints the conversations in the watched chats that would be
// raised for review, with their summaries, without changing anything. Add `--all` to treat every
// message as new and include plans that are already over.
if CommandLine.arguments.contains("--check-chats") {
    Task { @MainActor in
        let store = Store()
        let all = CommandLine.arguments.contains("--all")
        let now = Date()
        print("On-device model: \(PlanSummariser.modelAvailable ? "available" : "not available")")
        for feed in store.state.feeds where feed.type == .chat {
            print("\n=== \(feed.name)")
            do {
                let chatID = Beeper.chatID(of: feed)
                let days = CommandLine.arguments.firstIndex(of: "--days").flatMap { Double(CommandLine.arguments[$0 + 1]) } ?? SourceReader.chatLookBackDays
                let since = now.addingTimeInterval(-days * 86400)
                let lines = try await Beeper.messages(chatID: chatID, since: since).compactMap { m in
                    SourceReader.chatPost(m, chatID: chatID).map { PlanFinder.line(from: $0, sender: SourceReader.chatSender(m)) }
                }
                // `--lines` prints every message too, to see what a conversation looked like.
                if CommandLine.arguments.contains("--lines") {
                    for l in lines { print("    \(AppDelegate.dayTimeFmt.string(from: l.sent)) \(l.mentionsWhen ? "*" : " ") \(l.sender): \(l.text.prefix(160).replacingOccurrences(of: "\n", with: " / "))") }
                }
                let convos = PlanFinder.conversations(lines)
                print("\(lines.count) messages in \(convos.count) conversations; \(lines.filter(\.mentionsWhen).count) name a time or day")
                // With --all, judge as if it were just after each conversation, so past plans show too.
                for convo in convos {
                    let at = all ? (convo.last?.sent ?? now).addingTimeInterval(60) : now
                    for r in PlanFinder.find(convo, newIDs: Set(convo.map(\.id)), feedID: feed.id, chatID: chatID, now: at) {
                        let s = await PlanSummariser.summarise(r, chatName: feed.name, now: at)
                        print("\n  \(s.isPlan ? "REVIEW" : "not a plan") [\(s.byAI ? "AI" : "guess")] \(s.title)")
                        print("    when: \(s.when) | where: \(s.place ?? "-") | who: \(s.who.joined(separator: ", ")) | open: \(s.undecided ?? "-")")
                        print("    \(s.summary)")
                        for l in r.lines { print("      \(l.mentionsWhen ? "*" : " ") \(l.sender): \(l.text.prefix(140).replacingOccurrences(of: "\n", with: " / "))") }
                    }
                }
            } catch {
                print("  error: \(error.localizedDescription)")
            }
        }
        exit(0)
    }
    RunLoop.main.run()
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
