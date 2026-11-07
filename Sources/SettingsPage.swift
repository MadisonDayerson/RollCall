import SwiftUI
import AppKit

// MARK: - Settings

struct SettingsPage: View {
    @ObservedObject var model: UIModel
    @StateObject private var place = Box("")
    @StateObject private var km = Box("")
    @StateObject private var days = Box("")
    @StateObject private var message = Box<String?>(nil)
    @StateObject private var saving = Box(false)

    var body: some View {
        let app = model.app
        Form {
            // Saves by itself, like the rest of Settings: numbers as you type, the place when you press Return
            // or leave the page (it's looked up on a map, so not on every keystroke).
            Section("Home area") {
                TextField("Suburb or town", text: $place.value)
                    .onSubmit(savePlace)
                TextField("Show rides within (km)", text: $km.value)
                    .onChange(of: km.value) { _, _ in saveNumbers() }
                TextField("Days ahead to show", text: $days.value)
                    .onChange(of: days.value) { _, _ in saveNumbers() }
                HStack(spacing: 6) {
                    if saving.value {
                        ProgressView().controlSize(.small)
                        Text("Looking up “\(place.value)”…").foregroundStyle(.secondary)
                    } else if let m = message.value {
                        Label(m, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    } else if let found = foundPlace {
                        Label("Found: " + found, systemImage: "checkmark.circle.fill")
                    }
                }
                .font(.callout)
                Text("Press Return after changing the suburb. Rides further away are hidden, except rides you add yourself, rides from your chats and your Facebook events.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Section("Chats") {
                LabeledContent("Beeper", value: Keychain.read() == nil ? "Not connected" : "Connected (read only)")
                Button(Keychain.read() == nil ? "Connect Beeper…" : "Change chats…") {
                    model.later { Task { await app.setUpBeeper() } }
                }
            }
            Section("Facebook") {
                FacebookCalendarBox(app: app, connected: app.facebookCalendarConnected, later: model.later)
                Toggle("Pick up Facebook event downloads automatically", isOn: Binding(
                    get: { model.store.state.settings.watchDownloads }, set: { app.setWatchDownloads($0) }))
            }
            Section("Riding together") {
                TogetherForm(app: app)
            }
            Section("General") {
                Toggle("Open RollCall when you log in", isOn: Binding(
                    get: { app.opensAtLogin }, set: { app.setOpensAtLogin($0) }))
                let maps = model.store.state.settings.mapsApp ?? .automatic
                Picker("Maps app for Route", selection: Binding(
                    get: { maps }, set: { model.store.state.settings.mapsApp = $0; model.store.save() })) {
                    ForEach(MapsApp.allCases, id: \.self) { Text($0.name).tag($0) }
                }
                Text(maps == .automatic ? "Apple Maps for a trip straight to the meeting place, Google Maps when the ride has stops. A route the organiser shared opens as they shared it."
                     : maps.holdsStops ? "Route goes from your suburb through the meeting place and any stops. A route the organiser shared opens as they shared it."
                     : "\(maps.name) links hold one place, so Route goes to the meeting place. A route the organiser shared opens as they shared it.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Open calendar") { app.openCalendarApp() }
                Button("Run setup…") { model.later { app.showSetup() } }
            }
            Section("Privacy") {
                Text("Your rides, chats and settings stay on this Mac, readable only by you. RollCall has no accounts, no tracking and no online AI, and it never posts or sends messages. Removing a chat also removes what RollCall kept from it.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Picker("Keep dismissed plans", selection: Binding(
                    get: { model.store.state.settings.keepDismissed },
                    set: { model.store.state.settings.keepDismissedDays = $0; model.store.forgetDismissedMessages(); model.store.save() })) {
                    Text("Don't keep").tag(0)
                    Text("1 day").tag(1)
                    Text("1 week").tag(7)
                    Text("2 weeks").tag(14)
                }
                Text("Plans you mark Not a ride wait under Reviewed on the To review page, with their messages, so you can still add one. After this long, the messages are deleted.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Privacy details") { app.open("https://github.com/MadisonDayerson/RollCall#your-privacy") }
                    Button("Delete all data…", role: .destructive) { model.later { app.deleteAllData() } }
                }
            }
            Section("Updates") {
                LabeledContent("Version", value: Updater.currentVersion)
                Toggle("Check for new versions automatically", isOn: Binding(
                    get: { model.store.state.settings.checkForUpdates ?? true },
                    set: { model.store.state.settings.checkForUpdates = $0; model.store.save() }))
                HStack {
                    Button("Check now") { model.later { Task { await app.checkForUpdates(manual: true) } } }
                    Button("Release notes") { app.open(Updater.releasesPage) }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onAppear(perform: load)
        .onDisappear(perform: savePlace)
    }

    /// "Footscray, VIC, Australia" once the home area has been found on the map.
    var foundPlace: String? {
        let st = model.store.state.settings
        let parts = [st.homeCity, st.homeRegion, st.homeCountry].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    func saveNumbers() {
        let st = model.store.state.settings
        guard let k = Double(km.value), k > 0, let d = Int(days.value), d > 0,
              k != st.radiusKm || d != st.daysAhead else { return }
        Task { _ = await model.app.setHomeArea(place: st.homeName, km: k, days: d) }
    }

    func savePlace() {
        let p = place.value.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty, !saving.value, p != model.store.state.settings.homeName || model.store.state.settings.homeRegion == nil else { return }
        saving.value = true
        message.value = nil
        Task {
            message.value = await model.app.setHomeArea(place: p, km: 0, days: 0)
            if message.value == nil { place.value = model.store.state.settings.homeName }  // just the suburb
            saving.value = false
        }
    }

    func load() {
        let s = model.store.state.settings
        place.value = s.homeName
        km.value = String(Int(s.radiusKm))
        days.value = String(s.daysAhead)
    }
}


/// Location sharing, voice chat, Discord and tags, used in setup and Settings. Saves by itself.
struct TogetherForm: View {
    let app: AppDelegate
    @StateObject private var t = Box(Together())
    @StateObject private var loaded = Box(false)
    @StateObject private var pending = Box<Task<Void, Never>?>(nil)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Share locations with", selection: $t.value.locationApp) {
                ForEach(LocationApp.allCases, id: \.self) { Text($0.name).tag($0) }
            }
            Picker("Voice chat", selection: $t.value.intercom) {
                ForEach(Intercom.allCases.filter { !$0.isCall && $0 != .other && $0 != .none }, id: \.self) { Text($0.name).tag($0) }
                Divider()
                ForEach([Intercom.discord, .whatsApp, .other, .none], id: \.self) { Text($0.name).tag($0) }
            }
            if t.value.intercom != .none {
                TextField(t.value.intercom == .discord ? "Voice channel (optional)" : "Group or channel (optional)",
                          text: $t.value.intercomGroup, prompt: Text(t.value.intercom.groupPrompt))
                Text(t.value.intercom.isCall
                     ? "Calendar events ask everyone to join the call before you leave."
                     : "\(t.value.intercom.name) pairs with your phone, not your Mac: set up the group in its phone app. Calendar events say which group to join.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            TextField("Discord invite link", text: $t.value.discord, prompt: Text("https://discord.gg/…"))
            TextField("Tags you post under", text: $t.value.tags, prompt: Text("#hooligoon #melbourneriders"))
            Text("Calendar events include these. Groups can have their own Discord and tags on the Sources page.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { if !loaded.value { t.value = app.store.state.settings.crew; loaded.value = true } }
        // Saves by itself a moment after you stop typing (the calendar is updated too, so not on every key).
        .onChange(of: t.value) { _, v in
            pending.value?.cancel()
            pending.value = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 800_000_000)
                if !Task.isCancelled { app.setTogether(v) }
            }
        }
        .onDisappear { pending.value?.cancel(); app.setTogether(t.value) }
    }
}

/// A group's own Discord and tags, on its Sources page.
struct CrewLinksEditor: View {
    let key: String
    @ObservedObject var model: UIModel
    @StateObject private var discord = Box("")
    @StateObject private var tags = Box("")
    @StateObject private var pending = Box<Task<Void, Never>?>(nil)

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Discord invite link", text: $discord.value, prompt: Text("Uses yours from Settings if empty"))
                    .textFieldStyle(.roundedBorder)
                TextField("Tags", text: $tags.value, prompt: Text("e.g. #hooligoon"))
                    .textFieldStyle(.roundedBorder)
                Text("Added to the calendar events for this group's rides.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } label: {
            Label("Riding with this group", systemImage: "person.2.wave.2")
        }
        .onAppear(perform: load)
        .onChange(of: key) { old, _ in
            // Picking another source reuses this view, so keep what was typed for the last one.
            pending.value?.cancel()
            model.app.setCrewLinks(old, CrewLinks(discord: discord.value, tags: tags.value))
            load()
        }
        // Saves by itself a moment after you stop typing.
        .onChange(of: discord.value) { _, _ in saveSoon() }
        .onChange(of: tags.value) { _, _ in saveSoon() }
        .onDisappear { pending.value?.cancel(); save() }
    }

    func load() {
        let l = model.store.state.crew[key]
        discord.value = l?.discord ?? ""
        tags.value = l?.tags ?? ""
    }

    func save() { model.app.setCrewLinks(key, CrewLinks(discord: discord.value, tags: tags.value)) }

    func saveSoon() {
        pending.value?.cancel()
        let k = key, l = CrewLinks(discord: discord.value, tags: tags.value)
        pending.value = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            if !Task.isCancelled { model.app.setCrewLinks(k, l) }
        }
    }
}
