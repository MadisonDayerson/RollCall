import SwiftUI

// RollCall's patches, shared by the Mac and iPhone apps.

/// A heading in spaced capitals, like the "ROLLCALL" under the logo.
struct PatchLabel: View {
    let text: String
    var count: Int? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(text.uppercased()).font(.caption.weight(.heavy)).tracking(1.8)
            if let count { Text("\(count)").font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(.tertiary) }
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

/// A ride's date as a small patch with a single frame: month, day and weekday. Filled (like the icon)
/// for rides you're going to, dashed for maybe, outlined while undecided, faded once skipped or past.
struct DateBadge: View {
    let date: Date
    let decision: Decision
    var needsCheck = false
    var past = false
    var scale: CGFloat = 1

    var body: some View {
        let filled = decision == .attending
        let ink: Color = filled ? Self.paper : .primary
        let outer = RoundedRectangle(cornerRadius: 9 * scale, style: .continuous)
        let small = Font.system(size: 8 * scale, weight: .bold)
        VStack(spacing: 1 * scale) {
            Text(Self.month.string(from: date).uppercased()).font(small).tracking(0.8 * scale)
            Text(Self.day.string(from: date))
                .font(.system(size: 22 * scale, weight: .black).width(.condensed)).monospacedDigit()
            Text(Self.weekday.string(from: date).uppercased()).font(small).tracking(0.8 * scale)
        }
        .foregroundStyle(ink)
        .frame(width: 42 * scale, height: 52 * scale)
        .background { if filled { outer.fill(Color.primary) } }
        .overlay {
            // 1.5pt draws on whole pixels on a Retina screen, so the frame stays crisp.
            outer.strokeBorder(Color.primary, style: StrokeStyle(lineWidth: 1.5 * scale,
                                                                 dash: decision == .maybe ? [3 * scale, 2 * scale] : []))
        }
        .overlay(alignment: .topTrailing) {
            if needsCheck {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 12 * scale, weight: .bold))
                    .background(Circle().fill(Self.paper))
                    .offset(x: 5 * scale, y: -5 * scale)
            }
        }
        // Fade the patch as one piece, so a filled patch's frame fades with it instead of showing darker.
        .compositingGroup()
        .opacity(decision == .skip ? 0.5 : past ? 0.7 : 1)
        // Choosing Going fills the patch in, rather than it snapping.
        .animation(.easeOut(duration: 0.2), value: decision)
        .accessibilityHidden(true)
    }

    private static func fmt(_ f: String) -> DateFormatter {
        let d = DateFormatter(); d.locale = Locale(identifier: "en_AU"); d.dateFormat = f; return d
    }
    static let month = fmt("MMM"), day = fmt("d"), weekday = fmt("EEE")

    /// What the page's text sits on, for lettering cut out of a filled patch.
    #if os(macOS)
    static let paper = Color(nsColor: .windowBackgroundColor)
    #else
    static let paper = Color(uiColor: .systemBackground)
    #endif
}
