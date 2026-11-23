import SwiftUI

/// Home area, how far and how far ahead to look, the maps app, and deleting everything.
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
                    Text("Home")
                } footer: {
                    if let problem { Text(problem).foregroundStyle(.red) } else { Text("Only your suburb is kept, never your address.") }
                }

                Section {
                    Picker("Open routes in", selection: Binding(get: { s.mapsApp ?? .automatic }, set: { v in model.change { $0.mapsApp = v } })) {
                        ForEach(MapsApp.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                } footer: {
                    Text("Automatic uses Apple Maps for a simple trip and Google Maps for rides with stops. A route the organiser shared always opens as it is.")
                }

                Section {
                    Button("Delete All RollCall Data", role: .destructive) { confirmDelete = true }
                } footer: {
                    Text("Group chats are read by RollCall on your Mac.")
                }
            }
            .navigationTitle("Settings")
            .onAppear { home = s.homeName }
            .confirmationDialog("Delete all RollCall data?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { model.deleteAllData() }
            } message: {
                Text("Your rides, sources and settings are removed from this device. The RollCall calendar stays in Calendar.")
            }
        }
    }
}
