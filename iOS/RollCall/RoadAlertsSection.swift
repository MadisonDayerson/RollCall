import SwiftUI

/// Where the road alerts key is pasted, and which alerts routes show, as on the Mac. The key is the rider's own free key
/// from the Transport Victoria Open Data Portal, kept in this device's keychain.
struct RoadAlertsSection: View {
    @Environment(PhoneModel.self) private var model
    @State private var key = ""

    var body: some View {
        let shown = model.state.settings.roadAlertsShown
        let saved = model.roadAlertsKeySaved
        Section {
            if saved {
                LabeledContent("Key", value: "Saved in your keychain")
                Button("Remove key", role: .destructive) { model.removeRoadAlertsKey() }
            } else {
                HStack {
                    SecureField("Paste your key", text: $key).onSubmit(save).submitLabel(.done)
                    Button("Save", action: save)
                        .buttonStyle(.borderless)
                        .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                Link("Get a key", destination: URL(string: RoadAlerts.signUpPage)!)
            }
            Picker("Road alerts on routes", selection: Binding(get: { shown }, set: { choice in
                model.change { $0.roadAlerts = choice }
                // Booked roadworks kept on this device aren't needed any more.
                if choice != .currentAndPlanned { RoadAlerts.forget() }
            })) {
                ForEach(RoadAlertsShown.allCases, id: \.self) { Text($0.name).tag($0) }
            }
            .pickerStyle(.inline)
            .disabled(!saved)
        } header: {
            PatchLabel(text: "Road alerts")
        } footer: {
            Text(saved ? shown.help : RoadAlerts.about)
        }
    }

    private func save() {
        if model.saveRoadAlertsKey(key) { key = "" }
    }
}
