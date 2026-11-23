import AppKit
import SwiftUI
import UserNotifications

extension AppDelegate {
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
        switch Dialogs.run(a) {
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
}
