import AppKit

/// The RollCall, File, Edit, View, Window and Help menus at the top of the screen while a window is open.
@MainActor
enum AppMenu {
    static func install(for d: AppDelegate) {
        let main = NSMenu()

        func item(_ title: String, _ action: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command,
                  target: AnyObject? = nil) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            i.target = target
            return i
        }
        func menu(_ title: String, _ items: [NSMenuItem]) -> NSMenu {
            let m = NSMenu(title: title)
            items.forEach(m.addItem)
            let holder = NSMenuItem()
            holder.submenu = m
            main.addItem(holder)
            return m
        }

        _ = menu("RollCall", [
            item("About RollCall", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            item("Check for Updates…", #selector(AppDelegate.checkForUpdatesMenu), target: d),
            .separator(),
            item("Settings…", #selector(AppDelegate.showSettingsMenu), ",", target: d),
            item("Set Up RollCall…", #selector(AppDelegate.openSetupMenu), target: d),
            .separator(),
            item("Hide RollCall", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("Quit RollCall", #selector(NSApplication.terminate(_:)), "q"),
        ])
        _ = menu("File", [
            item("Add…", #selector(AppDelegate.openAddMenu), "n", target: d),
            item("Type a Ride In…", #selector(AppDelegate.addManualMenu), target: d),
            item("Paste a Post or Message…", #selector(AppDelegate.addFromPostMenu), target: d),
            item("Import a Calendar File…", #selector(AppDelegate.importMenu), "o", [.command, .shift], target: d),
            .separator(),
            item("Refresh Now", #selector(AppDelegate.refreshNow), "r", target: d),
            .separator(),
            item("Close Window", #selector(NSWindow.performClose(_:)), "w"),
        ])
        // Standard edit commands, so copy and paste work in the window's text fields.
        _ = menu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
        ])
        let pages: [(String, UIModel.Page)] = [("Rides", .rides), ("To Review", .review), ("Sources", .sources), ("Settings", .settings)]
        _ = menu("View", pages.enumerated().map { n, p in
            let i = item(p.0, #selector(AppDelegate.showPageMenu(_:)), "\(n + 1)", target: d)
            i.representedObject = p.1.rawValue
            return i
        } + [
            .separator(),
            item("Show Sidebar", #selector(NSSplitViewController.toggleSidebar(_:)), "s", [.command, .control]),
            item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]),
        ])
        // macOS adds its own tiling (Move & Resize, Fill, Centre) to the menu marked as the Window menu.
        let windowMenu = menu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:))),
            .separator(),
            item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))),
        ])
        let helpMenu = menu("Help", [
            item("RollCall Help", #selector(AppDelegate.helpMenu), "?", target: d),
        ])
        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
        NSApp.helpMenu = helpMenu
    }
}
