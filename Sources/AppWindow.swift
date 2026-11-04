import AppKit
import SwiftUI

extension AppDelegate {
    // MARK: - Window

    @objc func openWindowMenu() { showWindow() }
    @objc func openPostsMenu() { showWindow(page: .review) }
    @objc func openAddMenu() { showWindow(page: .sources, add: true) }
    @objc func showSettingsMenu() { showWindow(page: .settings) }
    @objc func showPageMenu(_ sender: NSMenuItem) {
        showWindow(page: (sender.representedObject as? String).flatMap(UIModel.Page.init(rawValue:)))
    }
    @objc func addManualMenu() { addManual() }
    @objc func addFromPostMenu() { addFromPost() }
    @objc func importMenu() { importICS() }
    @objc func checkForUpdatesMenu() { Task { await checkForUpdates(manual: true) } }
    @objc func helpMenu() { open("https://github.com/MadisonDayerson/RollCall#readme") }

    func showWindow(page: UIModel.Page? = nil, add: Bool = false) {
        if let page { ui.page = page }
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 640),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "RollCall"
            let host = NSHostingController(rootView: MainView(model: ui))
            // The window keeps the size it's given (snapped to half or a quarter of the screen) instead of growing to fit.
            host.sizingOptions = []
            w.contentViewController = host
            w.setContentSize(NSSize(width: 980, height: 640))
            // Small enough to tile into a quarter of a laptop screen; narrow windows show one column at a time.
            w.minSize = NSSize(width: 480, height: 340)
            w.isReleasedWhenClosed = false
            w.setFrameAutosaveName("RollCallWindow")
            w.delegate = self
            if !w.setFrameUsingName("RollCallWindow") { w.center() }
            window = w
        }
        // Show in the Dock and ⌘-Tab while the window is open.
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if add { ui.showAdd = true }
    }

    /// For checking the design: saves a picture of each page of the window.
    func saveSnapshots(to folder: URL) async {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // `--dark` checks how everything looks in dark mode.
        if CommandLine.arguments.contains("--dark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
        func snap(_ name: String, _ w: NSWindow?) async {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            // An app may capture its own windows; this includes the sidebar's translucency.
            guard let w, let img = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(w.windowNumber),
                                                           [.boundsIgnoreFraming, .bestResolution]) else { return }
            try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?
                .write(to: folder.appendingPathComponent(name + ".png"))
        }
        showWindow(page: .rides)
        // `--snapshot-size 640x400` checks how the window looks tiled into a corner of the screen.
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot-size"), i + 1 < CommandLine.arguments.count {
            let wh = CommandLine.arguments[i + 1].split(separator: "x").compactMap { Double($0) }
            if wh.count == 2 { window?.setContentSize(NSSize(width: wh[0], height: wh[1])); window?.center() }
        }
        if ui.rides().isEmpty { ui.rideFilter = .skipped }
        ui.selectedRide = ui.rides().first?.id
        await snap("1-rides", window)
        let filter = ui.rideFilter
        ui.rideFilter = .past
        // A sample finished ride if there isn't a real one (never saved: it's removed straight after).
        let pastDemo: RideEvent? = store.past().isEmpty ? RideEvent(
            id: "demo:past", title: "Sunday breakfast run, Black Spur", start: Date().addingTimeInterval(-2 * 86400),
            end: Date().addingTimeInterval(-2 * 86400 + 4 * 3600), allDay: false, location: "Coldstream VIC", notes: "",
            url: nil, source: "manual", sourceName: "Added by you", lastSeen: Date()) : nil
        if let pastDemo { store.state.events[pastDemo.id] = pastDemo; store.state.decisions[pastDemo.id] = .attending }
        ui.selectedRide = store.past().first?.id
        await snap("1-past", window)
        if let pastDemo { store.state.events[pastDemo.id] = nil; store.state.decisions[pastDemo.id] = nil }
        ui.rideFilter = filter
        // Back from another tab: the list must redraw cleanly, with no rows left over from the last one.
        ui.selectedRide = nil
        await snap("1-rides-again", window)
        ui.page = .review
        // Show a sample plan if there's nothing real to review (never saved: it's removed straight after).
        while refreshing { try? await Task.sleep(nanoseconds: 500_000_000) }
        let demo = store.state.reviews.values.contains { $0.status == .open } ? nil : demoReview()
        if let demo { store.state.reviews[demo.id] = demo; ui.objectWillChange.send() }
        await snap("2-review", window)
        if let demo { store.state.reviews[demo.id] = nil; ui.objectWillChange.send() }
        ui.page = .sources
        ui.selectedSource = nil
        await snap("3-sources-list", window)
        ui.selectedSource = store.state.feeds.first(where: { $0.type == .forum })?.id
        await snap("3-sources-forum", window)
        ui.selectedSource = store.state.feeds.first(where: { $0.type == .chat })?.id
        await snap("4-sources-chat", window)
        ui.selectedSource = store.state.instagram.first.map { "instagram:" + $0.handle }
        await snap("5-sources-instagram", window)
        ui.selectedSource = "yours"
        await snap("6-sources-yours", window)
        ui.selectedSource = "facebook"
        await snap("6-sources-facebook", window)
        ui.page = .settings
        await snap("7-settings", window)
        ui.showAdd = true
        try? await Task.sleep(nanoseconds: 800_000_000)
        await snap("8-add", window?.attachedSheet)
        ui.showAdd = false
        window?.close()
        showSetup()
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot-size"), i + 1 < CommandLine.arguments.count {
            let wh = CommandLine.arguments[i + 1].split(separator: "x").compactMap { Double($0) }
            if wh.count == 2 { setupWindow?.setContentSize(NSSize(width: max(520, wh[0]), height: max(400, wh[1]))) }
        }
        for step in SetupModel.Step.allCases {
            setup.go(step)
            if step == .messages { await setup.checkBeeper() }
            await snap("9-setup-\(step.rawValue)-\(step)", setupWindow)
        }
        setup.go(.messages)
        for g in SetupModel.GuideStep.allCases {
            setup.guide = g
            await snap("10-beeper-\(g.rawValue)-\(g)", setupWindow)
        }
        setup.guide = nil
        setupWindow?.close()
    }

    func demoReview() -> PlanReview {
        let now = Date()
        let lines = [("Alex", "Thinking about going for a ride Saturday arvo. Anyone want to join?"),
                     ("Jordan", "Keen! Could meet at Shell Coldstream 2pm and do the Black Spur?"),
                     ("Alex", "Sounds good, see you there"),
                     ("Casey", "Might join if the weather holds")].enumerated().map { i, m in
            ChatLine(id: "demo\(i)", sender: m.0, sent: now.addingTimeInterval(Double(i - 4) * 300), text: m.1,
                     mentionsWhen: PlanFinder.mentionsWhen(m.1))
        }
        let saturday = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 14, weekday: 7), matchingPolicy: .nextTime)
        let summary = PlanSummary(title: "Saturday Black Spur ride", when: "Saturday afternoon, 2pm", start: saturday, hasTime: true,
                                  place: "Shell Coldstream", who: ["Alex", "Jordan"], undecided: "Whether Casey is coming",
                                  summary: "Alex suggested a Saturday afternoon ride. Jordan proposed meeting at Shell Coldstream at 2pm and riding the Black Spur, and Alex agreed.",
                                  isPlan: true, byAI: true)
        return PlanReview(id: "plan:demo", feedID: store.state.feeds.first { $0.type == .chat }?.id ?? "", chatID: "demo",
                          lines: lines, summary: summary, status: .open, created: now, updated: now)
    }

    /// Clicking the Dock icon brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func windowWillClose(_ notification: Notification) {
        let closing = notification.object as? NSWindow
        if closing === setupWindow, !store.state.setupDone, !CommandLine.arguments.contains("--snapshots") {
            // Closing the wizard counts as skipping it; the menu can open it again.
            store.state.setupDone = true
            store.save()
        }
        let stillOpen = [window, setupWindow].contains { $0 != nil && $0 !== closing && $0!.isVisible }
        if !stillOpen { NSApp.setActivationPolicy(.accessory) }
    }

    // MARK: - Setup

    @objc func openSetupMenu() { showSetup() }

    func showSetup() {
        if setupWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 620),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = "Set up RollCall"
            let host = NSHostingController(rootView: SetupView(model: setup))
            host.sizingOptions = []
            w.contentViewController = host
            w.setContentSize(NSSize(width: 660, height: 620))
            w.minSize = NSSize(width: 520, height: 400)
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            setupWindow = w
        }
        setup.go(.welcome)
        NSApp.setActivationPolicy(.regular)
        setupWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func finishSetup(openWindow: Bool) {
        store.state.setupDone = true
        store.save()
        setupWindow?.close()
        if openWindow { showWindow(page: .rides) }
        Task { await refresh() }
    }
}
