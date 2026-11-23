import Foundation

extension AppDelegate {
    /// Shares rides, choices and sources with RollCall on iPhone and iPad through iCloud Drive, and takes in theirs.
    func syncDevices() {
        guard store.state.settings.syncDevices == true, !Store.picturesOnly, let folder = Sync.macFolder else { return }
        let before = try? Store.encoder.encode(store.state)
        do {
            for id in try Sync.run(store, folder: folder, name: "Mac") { syncCalendar(id) }
            syncProblem = nil
        } catch {
            syncProblem = error.localizedDescription
        }
        // Saved only when something came in, so the window isn't redrawn every minute for nothing.
        if (try? Store.encoder.encode(store.state)) != before {
            store.save()
            updateBadge()
        }
    }

    func setSyncDevices(_ on: Bool) {
        store.state.settings.syncDevices = on
        store.save()
        syncDevices()
    }
}
