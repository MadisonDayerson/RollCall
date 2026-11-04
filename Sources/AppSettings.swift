import AppKit
import SwiftUI
import ServiceManagement

extension AppDelegate {
    // MARK: - Removing

    /// The one way out, for anything on the Sources page.
    func removeSource(_ id: String) {
        if id.hasPrefix("instagram:") {
            let h = String(id.dropFirst("instagram:".count))
            guard Dialogs.confirm("Remove @\(h)?", "It won't be on your list of accounts to check any more.", ok: "Remove") else { return }
            store.state.instagram.removeAll { $0.handle == h }
        } else if let feed = store.state.feeds.first(where: { $0.id == id }) {
            guard Dialogs.confirm("Remove \(feed.name)?",
                                  "Its rides will disappear from the list. Rides you marked Going stay in your calendar.",
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
        store.state.reviews = store.state.reviews.filter { $0.value.feedID != id }
        for (eid, e) in store.state.events where e.source == id && store.decision(eid) != .attending {
            store.state.events[eid] = nil
        }
    }

    @objc func removeRide(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        removeRide(id: id)
    }

    @objc func editRide(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        editRide(id: id)
    }

    /// Opens the ride's details to change. The changes stay through refreshes and go to the calendar.
    func editRide(id: String) {
        guard let ride = store.state.events[id] else { return }
        let hours = ride.end.map { max(0.5, $0.timeIntervalSince(ride.start) / 3600) } ?? 3
        let shownStart = ride.allDay ? Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: ride.start) ?? ride.start : ride.start
        let going = store.decision(id) == .attending && store.state.calendarItems[id] != nil
        guard let r = Dialogs.manualRide(
            prefill: .init(title: ride.title, start: shownStart, hours: ride.allDay ? 24 : hours,
                           location: ride.location, link: ride.url ?? "", notes: ride.notes),
            note: going ? "Your changes go to the calendar too, and stay when RollCall checks the source again."
                        : "Your changes stay when RollCall checks the source again.",
            heading: "Edit ride", ok: "Save") else { return }
        // An all-day ride stays all day unless its start or length was changed.
        let allDay = ride.allDay && r.start == shownStart && r.hours == 24
        var link: String? = r.link.isEmpty ? nil : r.link
        if let l = link, !l.lowercased().hasPrefix("http") { link = "https://" + l }
        let edit = RideEdit(title: r.title, start: allDay ? ride.start : r.start,
                            end: allDay ? ride.end : r.start.addingTimeInterval(r.hours * 3600), allDay: allDay,
                            location: r.location, notes: r.notes, url: link)
        // Every copy of a cross-posted ride gets the change, so the copies still match and show as one ride.
        var e = ride
        for copy in [ride] + store.copies(of: ride) {
            store.state.rideEdits[copy.id] = edit
            e = copy.applying(edit)
            e.distanceKm = store.distance(e)
            store.state.events[copy.id] = e
            syncCalendar(copy.id)
        }
        store.save()
        NotificationCenter.default.post(name: Store.changed, object: nil)
        updateBadge()
        if e.latitude == nil, !e.location.isEmpty {
            Task { await geocoder.fill(store); store.save(); NotificationCenter.default.post(name: Store.changed, object: nil) }
        }
    }

    /// Removes the ride and every cross-posted copy of it. Rides from a source stay removed when it's checked again.
    func removeRide(id: String) {
        guard let ride = store.state.events[id] else { return }
        for e in [ride] + store.copies(of: ride) {
            store.state.decisions[e.id] = .skip
            syncCalendar(e.id)
            store.state.events[e.id] = nil
            store.state.decisions[e.id] = nil
            store.state.rideEdits[e.id] = nil
            store.state.removedRides[e.id] = e.start
        }
        store.save()
        NotificationCenter.default.post(name: Store.changed, object: nil)
        updateBadge()
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
            // Only the suburb and a rough spot (about 1 km) are kept, never a street address.
            store.state.settings.homeName = found.city ?? place
            store.state.settings.homeLatitude = Store.rough(found.latitude)
            store.state.settings.homeLongitude = Store.rough(found.longitude)
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

    var launchedAtLogin: Bool {
        let e = NSAppleEventManager.shared().currentAppleEvent
        return e?.eventID == kAEOpenApplication && e?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
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

    /// Removes everything RollCall keeps on this Mac (rides, chat excerpts, sources, settings, the Beeper key
    /// and the login item), then quits. The RollCall calendar is the user's own and stays in Calendar.
    func deleteAllData() {
        guard Dialogs.confirm("Delete all RollCall data?",
                              "This removes your saved rides, chat excerpts, sources and settings from this Mac, disconnects Beeper, and quits RollCall. It can't be undone.\n\nThe RollCall calendar stays in Calendar. You can delete it there if you like.",
                              ok: "Delete and Quit") else { return }
        setOpensAtLogin(false)
        Keychain.delete()
        try? FileManager.default.removeItem(at: Store.folder)
        if let id = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: id) }
        Net.removeOldCache()
        exit(0)  // straight out, so nothing is saved again on the way
    }
}
