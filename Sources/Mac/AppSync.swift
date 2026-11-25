import Foundation

extension AppDelegate {
    /// Shares rides, choices and sources with RollCall on iPhone and iPad through iCloud Drive, and takes in theirs.
    func syncDevices() {
        guard store.state.settings.syncDevices == true, !Store.picturesOnly, let folder = Sync.macFolder else { return }
        let before = try? Store.encoder.encode(store.state), problemBefore = syncProblem
        do {
            let (changed, problem) = try Sync.run(store, folder: folder, name: Sync.macName)
            // Without access there's nothing to do, and this runs by itself, so it's no time to ask for it.
            if calendar.authorised { changed.forEach(syncCalendar) }
            syncProblem = problem
        } catch {
            syncProblem = "Couldn't share: \(error.localizedDescription)"
        }
        // Saved only when something came in, so the window isn't redrawn every minute for nothing.
        if (try? Store.encoder.encode(store.state)) != before {
            store.save()
            updateBadge()
        } else if syncProblem != problemBefore {
            NotificationCenter.default.post(name: Store.changed, object: nil)
        }
    }

    func setSyncDevices(_ on: Bool) {
        store.state.settings.syncDevices = on
        syncProblem = nil
        store.save()
        syncDevices()
    }
}
