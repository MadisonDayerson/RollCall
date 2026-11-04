import AppKit
import SwiftUI

extension AppDelegate {
    // MARK: - Adding

    /// The one way in: works out what a pasted link is and adds it the right way.
    func add(link raw: String) {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
        let lower = s.lowercased()
        if FeedLinks.facebookCalendar(s) != nil {
            connectFacebookCalendar(link: s)
        } else if Store.facebookEventID(s) != nil || Store.facebookShareLink(s) != nil {
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

    var facebookCalendarConnected: Bool { store.state.feeds.contains { $0.id == FeedLinks.facebookCalendarID } }

    /// Adds Facebook's calendar of your events, after checking Facebook sends it.
    func connectFacebookCalendar(link: String) {
        guard let feed = FeedLinks.facebookCalendar(link) else {
            Dialogs.info("That isn't your Facebook events calendar link",
                         "On Facebook's Events page, right-click “Add to calendar” and choose “Copy Link”. The link starts with https://www.facebook.com/events/ical/")
            return
        }
        Task {
            do {
                _ = try await Fetcher.download(feed.url)
            } catch {
                Dialogs.info("Facebook didn't send your events",
                             "\(error.localizedDescription)\n\nCopy the link from Facebook again and paste it. Until then, you can still add Facebook events one at a time with +.")
                return
            }
            store.state.feeds.removeAll { $0.id == feed.id }
            store.state.feeds.append(feed)
            store.save()
            await checkFeed(feed.id)
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
        let fbID = Store.facebookEventID(vals[0])
        guard let eventURL = fbID.map({ "https://www.facebook.com/events/\($0)/" }) ?? Store.facebookShareLink(vals[0]) else {
            Dialogs.info("That doesn't look like a Facebook event link",
                         "On the event page, click Share → Copy link, and paste that. It looks like https://www.facebook.com/events/1234567890 or https://www.facebook.com/share/…")
            return
        }
        if !vals[1].isEmpty {
            if let fbID {
                store.state.facebookGroups[fbID] = vals[1]
                if var e = store.state.events["facebook:\(fbID)"] { e.groupURL = vals[1]; store.state.events[e.id] = e }
            } else {
                // A share link has no event number: the group goes with the next event downloaded from Facebook.
                pendingFacebookGroup = (vals[1], Date())
            }
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
                            allDay: false, location: r.location, notes: r.notes, url: link)
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
        Dialogs.info("Imported \(n) event\(n == 1 ? "" : "s")", "They're on the Rides page, where you can choose Going, Maybe or Skip.")
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
                let r = store.upcoming(oneEach: false).filter { $0.source == feed.id }.count
                let undated = (store.state.recentPosts[feed.id] ?? []).count
                var msg = "Found \(r) upcoming ride\(r == 1 ? "" : "s") nearby."
                if undated > 0 { msg += " \(undated) post\(undated == 1 ? "" : "s") without a date are under Posts to look at." }
                if feed.type == .forum || feed.type == .posts { msg += "\n\nNew posts are checked every \(feed.interval / 60) hours (change it under Sources). Rides marked ? had their date read from the post text, so check it before going." }
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
                             + "\n\nIf the site only posts rides as news or photos, use Paste a post or message (under +) for each one.")
            }
        }
    }

    func addFromPost(link: String = "") {
        guard let post = Dialogs.pastedPost(link: link), !(post.text.isEmpty && post.link.isEmpty) else { return }
        // Apple Intelligence (when it's on) reads the post too, for what RollCall's own rules miss.
        Task { addFromPost(post, details: post.text.isEmpty ? nil : await RideDetails.extract(RideDetails.input(post: post.text))) }
    }

    private func addFromPost(_ post: (link: String, text: String), details d: RideDetails.Details?) {
        var link = post.link
        if !link.isEmpty, !link.lowercased().hasPrefix("http") { link = "https://" + link }
        if link.isEmpty, let l = d?.link { link = l }
        var found = TextDetect.scan(post.text, daysAhead: 365)
        if let ds = d?.start, found.start == nil || !found.hasTime { found.start = ds; found.hasTime = d?.hasTime ?? false }
        if found.address == nil { found.address = d?.meet }
        var start = found.start ?? Dialogs.nextSundayMorning()
        if found.start != nil, !found.hasTime {
            start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: start) ?? start
        }
        var notes: [String] = []
        if d != nil { notes.append("Apple Intelligence helped fill this in, on this Mac.") }
        notes.append(found.start == nil ? "No date found in the text, so pick one below."
                     : found.hasTime ? "Date and time found in the text. Check they're right."
                     : "A date was found but no time, so 9am is filled in. Check it.")
        if found.address == nil { notes.append("No address found. Type the meeting place if you know it.") }
        guard let r = Dialogs.manualRide(
            prefill: .init(title: d?.title ?? TextDetect.title(from: post.text), start: start, hours: d?.hours ?? 4,
                           location: found.address ?? "", link: link,
                           notes: post.text.count > 1000 ? String(post.text.prefix(1000)) + "…" : post.text),
            note: notes.joined(separator: " ")) else { return }

        var url: String? = r.link.isEmpty ? nil : r.link
        if let l = url, !l.lowercased().hasPrefix("http") { url = "https://" + l }
        let fbID = url.flatMap(Store.facebookEventID)
        let isInstagram = url?.contains("instagram.com") ?? false
        let source = fbID != nil ? "facebook" : isInstagram ? "instagram" : "manual"
        let item = ICSEvent(uid: fbID.map { "e\($0)@facebook.com" } ?? "post-\(UUID().uuidString)",
                            title: r.title, start: r.start, end: r.start.addingTimeInterval(r.hours * 3600),
                            allDay: false, location: r.location,
                            notes: r.notes, url: url)
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
        // Connected again: chats that couldn't be read get another go straight away.
        for f in store.state.feeds where f.type == .chat && !added.contains(where: { $0.id == f.id }) && store.state.feedErrors[f.id] != nil {
            await checkFeed(f.id)
        }
        if let f = added.first { ui.selectedSource = f.id }
    }
}
