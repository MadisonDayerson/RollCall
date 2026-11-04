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
    /// Source id -> last automatic or manual read, even a failed one, so failing sources wait their turn.
    var lastTried: [String: Date] = [:]
    /// A group link given with a Facebook share link, waiting for that event's download.
    var pendingFacebookGroup: (String, Date)?

    func applicationDidFinishLaunching(_ note: Notification) {
        Net.removeOldCache()
        store.minimiseHome()
        AppMenu.install(for: self)
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
            tidyChatNotes()
            await refresh(dueOnly: true)
        }
        let quiet = CommandLine.arguments.contains("--snapshots") || CommandLine.arguments.contains("--window")
        if !store.state.setupDone && !CommandLine.arguments.contains("--snapshots") { showSetup() }
        // Opening RollCall opens its window; starting with the Mac (Open at login) stays in the menu bar.
        else if store.state.setupDone && !quiet && !launchedAtLogin { showWindow(page: .rides) }
        if let i = CommandLine.arguments.firstIndex(of: "--window") {
            // `--window sources` opens straight to a page (handy for checking the window).
            let page = CommandLine.arguments.dropFirst(i + 1).first.flatMap(UIModel.Page.init(rawValue:))
            showWindow(page: page)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshots"), i + 1 < CommandLine.arguments.count {
            Task { await saveSnapshots(to: URL(fileURLWithPath: CommandLine.arguments[i + 1])) }
        }
        // Every minute: Facebook downloads, and any source whose own interval has passed.
        timers.append(Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scanDownloads(); await self?.refresh(dueOnly: true) }
        })
        // New versions: shortly after opening, then daily.
        if !CommandLine.arguments.contains("--snapshots") {
            Task { try? await Task.sleep(nanoseconds: 20_000_000_000); await checkForUpdates(manual: false) }
        }
        timers.append(Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.checkForUpdates(manual: false) }
        })
    }
}

extension RideEvent {
    /// What the "open" button for this ride's link should say: a word or two, with `linkHelp` as its tooltip.
    var linkLabel: String {
        guard let url else { return "" }
        return isFacebook || url.contains("meetup.com") ? "RSVP"
            : url.hasPrefix(Beeper.chatLinkPrefix) ? "Open chat"
            : url.contains("instagram.com") || needsCheck == true ? "Open post" : "Open event"
    }

    var hasRoute: Bool { !location.isEmpty || Route.link(in: notes) != nil }

    var linkHelp: String {
        guard let url else { return "" }
        return isFacebook ? "Open the event on Facebook to RSVP"
            : url.contains("meetup.com") ? "Open the event on Meetup to RSVP"
            : url.contains("instagram.com") ? "Open the Instagram post"
            : url.hasPrefix(Beeper.chatLinkPrefix) ? "Open the message in Beeper"
            : needsCheck == true ? "Open the post the ride came from" : "Open the event page"
    }
}

import CoreLocation

enum CLGeocoderShim {
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

// For tuning: `RollCall --check-chats` prints the conversations in the chosen chats that would be
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
