import SwiftUI

/// RollCall's one blue glow: near-white blue letters in a deep blue haze, like a neon sign.
enum Neon {
    static let core = Color(red: 0.62, green: 0.94, blue: 1.0)
    static let haze = Color(red: 0.1, green: 0.45, blue: 1.0)
}

extension View {
    /// A faint blue glow behind a page of glass cards, so the glass has something to bend and catch the light from.
    func glassBackdrop() -> some View { background { NeonBackdrop().ignoresSafeArea() } }

    /// The blue haze around the letters; `breath` softens it and spreads it a little further.
    func neonHaze(breath: Double = 0) -> some View {
        shadow(color: Neon.haze, radius: 2)
            .shadow(color: Neon.haze.opacity(1 - 0.5 * breath), radius: 6 + 4 * breath)
    }
}

/// A mask that shows letters from left to right, up to `lit` (0 to 1) with a soft leading edge.
struct NeonReveal: View {
    let lit: Double
    private static let edge: CGFloat = 14

    var body: some View {
        GeometryReader { g in
            HStack(spacing: 0) {
                Rectangle().frame(width: g.size.width)
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: Self.edge)
            }
            // The edge comes in from the left of the letters, and is past their right once they're all lit.
            .offset(x: (g.size.width + Self.edge) * (lit - 1))
        }
    }
}

/// RollCall's neon blue, softly spread from the top and bottom corners of the page.
private struct NeonBackdrop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        ZStack {
            #if os(macOS)
            Color(nsColor: .windowBackgroundColor)
            #else
            Color(.systemGroupedBackground)
            #endif
            RadialGradient(colors: [Neon.haze.opacity(dark ? 0.32 : 0.16), .clear], center: .topTrailing, startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Neon.core.opacity(dark ? 0.14 : 0.22), .clear], center: .bottomLeading, startRadius: 0, endRadius: 460)
        }
        .accessibilityHidden(true)
    }
}
