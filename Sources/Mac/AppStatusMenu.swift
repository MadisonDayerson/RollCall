import AppKit
import SwiftUI
import MapKit

extension AppDelegate {
    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(action("Open RollCall…", #selector(openWindowMenu), key: "o"))
        let toReview = possiblePlans().count
        if toReview > 0 { menu.addItem(action("To review (\(toReview))…", #selector(openPostsMenu))) }
        menu.addItem(action("Add a ride…", #selector(addRideMenu), key: "n"))
        menu.addItem(action("Add a source…", #selector(addSourceMenu)))
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

    func open(_ link: String?) {
        if let link, Beeper.chatParts(link) != nil {
            Task {
                do { try await Beeper.focus(link: link) } catch {
                    Dialogs.info("Couldn't open the chat in Beeper", error.localizedDescription)
                }
            }
            return
        }
        if let url = Web.link(link) { NSWorkspace.shared.open(url) }
    }

    /// Apple Maps is on this Mac (it can be removed).
    var hasAppleMaps: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Maps") != nil }

    /// Opens the ride's route: the organiser's shared route, or else directions in the maps app you pick
    /// (or the one chosen in Settings).
    func openRoute(_ ride: RideEvent, in chosen: MapsApp? = nil) {
        Task {
            guard let link = await store.directions(for: ride, in: chosen, hasAppleMaps: hasAppleMaps) else { return }
            // Apple Maps links open the Maps app; the others are web pages.
            if link.hasPrefix("http") { open(link) } else if let url = URL(string: link) { NSWorkspace.shared.open(url) }
        }
    }
}
