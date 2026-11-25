import SwiftUI

/// What Refresh found about a ride, as on the Mac: each detail with where it came from, added one at a time.
struct RideFindings: View {
    @Environment(PhoneModel.self) private var model
    let id: String
    let lookup: RideSearch.Lookup

    var body: some View {
        Section {
            switch lookup {
            case .looking(let step):
                HStack(spacing: 8) { ProgressView(); Text(step).foregroundStyle(.secondary) }
            case .done(let found, _):
                ForEach(found) { f in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(f.label).font(.footnote).foregroundStyle(.secondary)
                            Text(f.value).textSelection(.enabled)
                            Text("From \(f.from)").font(.footnote).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Add") { model.useFinding(f, rideID: id) }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Add \(f.label): \(f.value)")
                    }
                }
                Button("Done") { model.lookups[id] = nil }
            }
        } header: {
            PatchLabel(text: "More details")
        } footer: {
            if case .done(let found, let checked) = lookup, !found.isEmpty {
                Text("Apple Intelligence checked each of these is about this ride. Looked through \(checked).")
            }
        }
    }
}
