import SwiftUI

/// How the Rides tab shows the rides.
enum RidesLayout: String, CaseIterable {
    case list, week, month
    var name: String { rawValue.capitalized }
}

/// One section of the rides list: a heading that opens and closes, and its rides. Skipped and Past start closed, as on
/// the Mac; whatever you open or close is remembered.
struct RideSection: View {
    let section: PhoneModel.Section
    @AppStorage private var open: Bool

    init(section: PhoneModel.Section) {
        self.section = section
        _open = AppStorage(wrappedValue: !["Skipped", "Past"].contains(section.name), "open\(section.name)Rides")
    }

    var body: some View {
        Section {
            if open {
                ForEach(section.rides, id: \.id) { ride in
                    RideRow(ride: ride, past: section.name == "Past").tag(ride.id)
                }
            }
        } header: {
            Button { withAnimation { open.toggle() } } label: {
                HStack(spacing: 8) {
                    PatchLabel(text: section.name, count: section.rides.count)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .frame(minHeight: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // A heading's own grey on top of the label's would leave it too faint.
            .foregroundStyle(Color.primary)
            .accessibilityValue(open ? "Open" : "Closed")
        }
    }
}
