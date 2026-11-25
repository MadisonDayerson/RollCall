import SwiftUI

/// What the organiser wrote: the few lines that matter in plain words, with the whole thing under See more, as on the Mac.
struct RideAbout: View {
    let ride: RideEvent
    @State private var more = false

    var body: some View {
        let about = Brief.summary(of: ride.notes, location: ride.location)
        Section {
            ForEach(Array(about.items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.label).font(.footnote).foregroundStyle(.secondary)
                    Text(item.value).textSelection(.enabled)
                }
            }
            if let text = about.text { Text(text).textSelection(.enabled) }
            if let full = about.more {
                if more { Text(full).textSelection(.enabled) }
                Button(more ? "See less" : "See more") { more.toggle() }
            }
        } header: {
            PatchLabel(text: "About")
        }
    }
}
