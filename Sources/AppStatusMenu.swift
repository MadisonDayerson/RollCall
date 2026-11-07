import AppKit
import SwiftUI
import MapKit

extension AppDelegate {
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
        let toReview = possiblePlans().count
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
        // Black-and-white marks to match the window's date patches: filled for going, dashed for maybe.
        let symbol: String
        switch d {
        case .attending: symbol = "checkmark.circle.fill"
        case .maybe: symbol = "circle.dashed"
        case .skip: symbol = "xmark.circle"
        case .undecided: symbol = ride.needsCheck == true ? "questionmark.circle" : "circle"
        }
        let when = ride.allDay ? Self.dayFmt.string(from: ride.start) : Self.dayTimeFmt.string(from: ride.start)
        let item = NSMenuItem(title: "\(when)  ·  \(ride.title)", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: decisionName(d, needsCheck: ride.needsCheck == true))
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

        for (label, choice) in [("Going", Decision.attending), ("Maybe", .maybe), ("Skip", .skip)] {
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
        // The same items as the buttons on the ride's page.
        for (title, sel, object, enabled) in [("Open event", #selector(openLink(_:)), ride.url ?? "", ride.url != nil),
                                              ("Edit…", #selector(editRide(_:)), ride.id, true),
                                              ("Route", #selector(openMaps(_:)), ride.id, ride.hasRoute),
                                              ("Remove", #selector(removeRide(_:)), ride.id, true)] {
            let it = action(title, sel, enabled: enabled)
            it.representedObject = object
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
        // Links come from feeds and chats, so only web links open (never a file or an app on this Mac).
        guard let link, let url = URL(string: link), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc func openMaps(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String, let ride = store.state.events[id] { openRoute(ride) }
    }

    /// Directions for a ride: the organiser's own route if the description has one, otherwise from your
    /// suburb to the meeting place, any stops and the destination, in the maps app chosen in Settings.
    /// Automatic uses Apple Maps for a simple trip when it's on this Mac, and Google Maps for stops.
    func openRoute(_ ride: RideEvent) {
        if let link = Route.link(in: ride.notes) {
            open(link.replacingOccurrences(of: "http://", with: "https://"))
            return
        }
        // The maps apps already start from your suburb, so it isn't repeated as a stop.
        let places = Array(store.routePlaces(ride).drop { $0 == store.homePlace })
        guard let first = places.first else { return }
        let home = store.state.settings.homeCity?.nilIfEmpty
        let hasAppleMaps = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Maps") != nil
        var app = store.state.settings.mapsApp ?? .automatic
        if app == .automatic { app = places.count == 1 && hasAppleMaps ? .apple : .google }
        if app == .apple, !hasAppleMaps { app = .google }
        switch app {
        case .apple:
            if let url = URL(string: Route.appleMaps(from: home, to: first)) { NSWorkspace.shared.open(url) }
        case .waze:
            open(Route.waze(to: first))
        case .kurviger:
            let s = store.state.settings
            let home = CLLocationCoordinate2D(latitude: s.homeLatitude, longitude: s.homeLongitude)
            Task {
                let found = await RoutePlanner.locate(places, near: home) ?? []
                let points = ([home] + found).map { (latitude: $0.latitude, longitude: $0.longitude) }
                // A place Apple Maps couldn't find: Google Maps can still search for it by name.
                open(found.isEmpty ? Route.googleMaps(from: s.homeCity?.nilIfEmpty, through: places) : Route.kurviger(through: points))
            }
        default:
            open(Route.googleMaps(from: home, through: places))
        }
    }
}
