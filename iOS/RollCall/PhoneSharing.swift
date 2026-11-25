import SwiftUI

/// Sharing rides, choices and sources with RollCall on the Mac through a folder in iCloud Drive.
extension PhoneModel {

    static let folderKey = "macFolder"
    static func savedFolder() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: folderKey) else { return nil }
        var stale = false
        return try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale)
    }

    func shareWithMac(in folder: URL) {
        let allowed = folder.startAccessingSecurityScopedResource()
        defer { if allowed { folder.stopAccessingSecurityScopedResource() } }
        guard let bookmark = try? folder.bookmarkData() else {
            shareProblem = "Couldn't keep access to that folder. Choose it again."
            return
        }
        // Another folder, or the Mac hasn't shared yet.
        guard Sync.isMacs(folder) else {
            shareProblem = "RollCall on your Mac isn't sharing in that folder. Choose the RollCall folder in iCloud Drive. If that's the one, give iCloud a minute and choose it again."
            return
        }
        macFolder = folder
        guard share(joining: true) else {
            macFolder = nil
            return
        }
        store.noteRides()
        UserDefaults.standard.set(bookmark, forKey: Self.folderKey)
        store.save()
        state = store.state
    }

    func stopSharing() {
        if let folder = macFolder {
            let allowed = folder.startAccessingSecurityScopedResource()
            Sync.forget(folder: folder, name: UIDevice.current.model)
            if allowed { folder.stopAccessingSecurityScopedResource() }
        }
        UserDefaults.standard.removeObject(forKey: Self.folderKey)
        macFolder = nil
        lastShared = nil
        shareProblem = nil
        store.state.macChats = nil
        saved()
    }

    /// Takes in what the Mac changed since (called every minute while RollCall is open).
    func shareNow() {
        guard macFolder != nil else { return }
        saved()
    }

    /// False when nothing was shared. `shareProblem` says why, or which device's file was left for next time.
    @discardableResult
    func share(joining: Bool = false) -> Bool {
        guard let folder = macFolder else { return false }
        let allowed = folder.startAccessingSecurityScopedResource()
        defer { if allowed { folder.stopAccessingSecurityScopedResource() } }
        do {
            let (changed, problem) = try Sync.run(store, folder: folder, name: UIDevice.current.model, joining: joining)
            if calendar.authorised { for id in changed { syncCalendar(id) } }
            lastShared = Date()
            shareProblem = problem
            return true
        } catch {
            shareProblem = "Couldn't share: \(error.localizedDescription)"
            return false
        }
    }
}
