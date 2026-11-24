import SwiftUI

/// A ride in short, in lists and on Home: its date patch, name, time and place. Larger for your next ride.
struct RideSummary: View {
    @Environment(PhoneModel.self) private var model
    @Environment(\.dynamicTypeSize) private var textSize
    let ride: RideEvent
    var past = false
    var large = false

    var body: some View {
        // Very large text needs more lines.
        let wraps = textSize.isAccessibilitySize
        HStack(spacing: large ? 14 : 12) {
            DateBadge(date: ride.start, decision: model.decision(ride.id), needsCheck: ride.needsCheck == true, past: past,
                      scale: large ? 1.4 : 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(ride.title).font(large ? .title3.bold() : .headline).lineLimit(wraps ? nil : 2)
                Text(Format.when(ride)).font(.subheadline).foregroundStyle(.secondary)
                if let place = Format.place(ride) {
                    Text(place).font(.subheadline).foregroundStyle(.secondary).lineLimit(wraps ? nil : 1)
                }
            }
            .multilineTextAlignment(.leading)
        }
    }
}
