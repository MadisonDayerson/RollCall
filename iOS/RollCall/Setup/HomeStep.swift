import SwiftUI

/// Where you ride from: the one step that can't be skipped. Continue finds the suburb first.
struct HomeStep: View {
    @Environment(PhoneModel.self) private var model
    let next: () -> Void
    @State private var place = ""
    @State private var finding = false
    @State private var problem: String?

    var body: some View {
        let s = model.state.settings
        Form {
            StepHeader(title: "Where do you ride from?",
                       text: "RollCall shows rides within a distance of home. Rides from your own chats always show, wherever they are.")
            Section {
                TextField("Suburb or town, e.g. Ringwood VIC", text: $place)
                    .textContentType(.addressCity)
                    .submitLabel(.next)
                    .onSubmit(go)
                if let problem { ProblemLabel(text: problem) } else if let found = s.foundPlace { DoneLabel(text: "Found: \(found)") }
                Stepper("Within \(Int(s.radiusKm)) km", value: Binding(get: { s.radiusKm }, set: { v in model.change { $0.radiusKm = v } }),
                        in: 10...500, step: 10)
            } footer: {
                Text("Only your suburb is kept, never your address. You can change these later in Settings.")
            }
        }
        .modifier(SetupFooter(title: "Continue", working: finding, disabled: place.trimmingCharacters(in: .whitespaces).isEmpty, action: go))
        .modifier(StepCount(step: .home))
        .onAppear { if s.foundPlace != nil { place = s.homeName } }
    }

    private func go() {
        let s = model.state.settings
        // Already found: nothing to look up again.
        if s.foundPlace != nil, place == s.homeName { return next() }
        finding = true
        Task {
            problem = await model.setHome(place)
            finding = false
            if problem == nil { next() }
        }
    }
}
