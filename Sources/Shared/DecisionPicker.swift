import SwiftUI

/// Going, Maybe or Skip on a ride's page, on the Mac, iPhone and iPad. Nothing is chosen while a ride is undecided,
/// so undecided needs no button of its own; choosing the chosen one again leaves the ride undecided once more.
struct DecisionPicker: View {
    let decision: Decision
    let choose: (Decision) -> Void

    #if os(iOS)
    private static let padding: CGFloat = 11  // Tall enough to tap.
    #else
    private static let padding: CGFloat = 5
    #endif

    private static let choices: [(Decision, String)] = [(.attending, "Going"), (.maybe, "Maybe"), (.skip, "Skip")]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Self.choices, id: \.0) { d, name in
                let on = decision == d
                Button { choose(on ? .undecided : d) } label: {
                    Text(name)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Self.padding)
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .background(on ? Color.accentColor : Color.clear, in: .capsule)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(on ? "Choose again to leave it undecided" : "")
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityHint(on ? "Choose again to leave it undecided" : "")
            }
        }
        .padding(2)
        .background(Color.secondary.opacity(0.12), in: .capsule)
    }
}

extension Decision {
    /// In words, for VoiceOver.
    func spoken(needsCheck: Bool) -> String {
        switch self {
        case .attending: return "Going"
        case .maybe: return "Maybe"
        case .skip: return "Skipped"
        case .undecided: return needsCheck ? "New, check the date" : "New"
        }
    }
}
