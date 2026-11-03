import AppKit

/// Checks GitHub for a newer RollCall and installs it.
///
/// Releases live at github.com/MadisonDayerson/rollcall (made by release.sh). RollCall downloads the
/// new .dmg itself, swaps the app in place and reopens. Files an app downloads itself aren't marked as
/// "from the internet", so updates skip the Open Anyway step the first install needed.
@MainActor
enum Updater {
    nonisolated static let repo = "MadisonDayerson/rollcall"
    static var releasesPage: String { "https://github.com/\(repo)/releases/latest" }

    struct Release {
        var version: String
        var notes: String
        var page: String
        var dmg: URL?
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// "1.10" is newer than "1.9".
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.trimmingCharacters(in: CharacterSet(charactersIn: "vV ")).split(separator: ".").map { Int($0) ?? 0 }
        }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    /// The latest release, or nil when there isn't one (or GitHub can't be reached).
    static func latest() async throws -> Release? {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue(Web.userAgent, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20
        let (data, resp) = try await Net.session.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else { return nil }
        let assets = json["assets"] as? [[String: Any]] ?? []
        let dmg = assets.compactMap { $0["browser_download_url"] as? String }.first { isOurDownload($0) }
        return Release(version: tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV")),
                       notes: json["body"] as? String ?? "",
                       page: json["html_url"] as? String ?? releasesPage,
                       dmg: dmg.flatMap(URL.init(string:)))
    }

    /// Only a .dmg attached to RollCall's own releases on GitHub is ever downloaded.
    nonisolated static func isOurDownload(_ link: String) -> Bool {
        let l = link.lowercased()
        return l.hasPrefix("https://github.com/\(repo.lowercased())/releases/download/") && l.hasSuffix(".dmg")
            && !l.contains("..")
    }

    enum UpdateError: LocalizedError {
        case noDownload, notMounted, noApp, notRollCall, cantReplace(String)
        var errorDescription: String? {
            switch self {
            case .noDownload: return "The release doesn't have a RollCall download."
            case .notMounted: return "The download couldn't be opened."
            case .noApp: return "The download doesn't contain RollCall."
            case .notRollCall: return "The download didn't pass RollCall's safety check, so it wasn't installed."
            case .cantReplace(let why): return "RollCall couldn't replace itself (\(why))."
            }
        }
    }

    /// Downloads the release, puts the new app where this one is, and reopens it.
    static func install(_ r: Release) async throws {
        guard let dmgURL = r.dmg, isOurDownload(dmgURL.absoluteString) else { throw UpdateError.noDownload }
        let (tmp, _) = try await Net.session.download(from: dmgURL)
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("RollCall-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let dmg = work.appendingPathComponent("RollCall.dmg")
        try FileManager.default.moveItem(at: tmp, to: dmg)
        let mount = work.appendingPathComponent("mnt")
        guard run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-mountpoint", mount.path]) else {
            throw UpdateError.notMounted
        }
        defer { _ = run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }
        let newApp = mount.appendingPathComponent("RollCall.app")
        guard FileManager.default.fileExists(atPath: newApp.path) else { throw UpdateError.noApp }
        // It must be RollCall, with its code seal intact (nothing changed since it was built).
        guard Bundle(url: newApp)?.bundleIdentifier == Bundle.main.bundleIdentifier,
              run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path]) else { throw UpdateError.notRollCall }

        // Copy next to this app first, then swap, so a failed copy leaves the working app alone.
        let here = Bundle.main.bundleURL
        let staged = here.deletingLastPathComponent().appendingPathComponent(".RollCall-new.app")
        try? FileManager.default.removeItem(at: staged)
        guard run("/usr/bin/ditto", [newApp.path, staged.path]) else {
            throw UpdateError.cantReplace("no permission to write to \(here.deletingLastPathComponent().path)")
        }
        do {
            _ = try FileManager.default.replaceItemAt(here, withItemAt: staged)
        } catch {
            try? FileManager.default.removeItem(at: staged)
            throw UpdateError.cantReplace(error.localizedDescription)
        }
        // Reopen once this copy has quit.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", here.path]
        try p.run()
        NSApp.terminate(nil)
    }

    @discardableResult
    nonisolated static func run(_ tool: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }
}
