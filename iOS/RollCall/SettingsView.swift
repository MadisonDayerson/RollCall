import SwiftUI

/// Home area, how far and how far ahead to look, the maps app, road alerts, and deleting everything.
struct SettingsView: View {
    @Environment(PhoneModel.self) private var model
    @State private var home = ""
    @State private var problem: String?
    @State private var confirmDelete = false

    var body: some View {
        let s = model.state.settings
        NavigationStack {
            Form {
                Section {
                    TextField("Suburb or town", text: $home)
                        .onSubmit { Task { problem = await model.setHome(home) } }
                        .submitLabel(.done)
                    Stepper("Within \(Int(s.radiusKm)) km", value: Binding(get: { s.radiusKm }, set: { v in model.change { $0.radiusKm = v } }),
                            in: 10...500, step: 10)
                    Stepper("Up to \(s.daysAhead) days ahead", value: Binding(get: { s.daysAhead }, set: { v in model.change { $0.daysAhead = v } }),
                            in: 7...180, step: 7)
                } header: {
                    PatchLabel(text: "Home")
                } footer: {
                    if let problem { Text(problem).foregroundStyle(.orange) } else { Text("Only your suburb is kept, never your address.") }
                }

                Section {
                    Picker("Open routes in", selection: Binding(get: { s.mapsApp ?? .automatic }, set: { v in model.change { $0.mapsApp = v } })) {
                        ForEach(MapsApp.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                } footer: {
                    Text("Automatic uses Apple Maps for a simple trip and Google Maps for rides with stops. A route the organiser shared always opens as it is.")
                }

                RoadAlertsSection()

                Section {
                    if let folder = model.macFolder {
                        LabeledContent("Sharing through", value: "\(folder.lastPathComponent) folder")
                        if let last = model.lastShared, model.shareProblem == nil {
                            LabeledContent("Last shared", value: last.formatted(.relative(presentation: .named)))
                        }
                        Button("Stop sharing", role: .destructive) { model.stopSharing() }
                    } else {
                        MacFolderButton(title: "Share with RollCall on Mac…")
                    }
                    if let problem = model.shareProblem { ProblemLabel(text: "Couldn't share: \(problem)") }
                } header: {
                    PatchLabel(text: "Mac")
                } footer: {
                    Text(model.macFolder == nil
                         ? "On your Mac, open RollCall → Settings and turn on Share with RollCall on iPhone and iPad. Then tap above and choose the RollCall folder in iCloud Drive."
                         : "Your rides, Going/Maybe/Skip choices, ride changes and sources are shared with RollCall on your Mac, and it shares its own the same way. Rides from chats come without their messages: chats stay on the Mac.")
                }

                Section {
                    Button("Run setup…") { model.settingUp = true }
                    Button("Delete all data…", role: .destructive) { confirmDelete = true }
                } footer: {
                    Text("Group chats are read by RollCall on your Mac.")
                }
            }
            .navigationTitle("Settings")
            .onAppear { home = s.homeName }
            .confirmationDialog("Delete all RollCall data?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { model.deleteAllData() }
            } message: {
                Text("This removes your saved rides, sources and settings from this device. It can't be undone.\n\nThe RollCall calendar stays in Calendar. You can delete it there if you like.")
            }
        }
    }
}
