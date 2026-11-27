import SwiftUI

/// Apple's Liquid Glass, for the controls that float over a page (its bars and their buttons) and the cards on Home and the
/// Rides calendar, over a faint neon glow (`glassBackdrop`). What's on a card stays plain: glass never goes on glass.
/// Before macOS 26 they get the ordinary look.
extension View {
    /// A bar the page scrolls under.
    @ViewBuilder func floatingBar<Bar: View>(_ edge: VerticalEdge, @ViewBuilder bar: () -> Bar) -> some View {
        if #available(macOS 26, *) {
            safeAreaBar(edge: edge, spacing: 0, content: bar)
        } else {
            safeAreaInset(edge: edge, spacing: 0) { bar().frame(maxWidth: .infinity).background(.bar) }
        }
    }

    /// Keeps the toolbar's title and the tabs readable over a page of text scrolled under them.
    @ViewBuilder func clearTopEdge() -> some View {
        if #available(macOS 26, *) { scrollEdgeEffectStyle(.hard, for: .top) } else { self }
    }

    /// A card of glass with the panel's corners. The glass is behind what's on the card, so date patches and text keep
    /// their full black and white rather than taking on the glass's tint.
    @ViewBuilder func glassCard() -> some View {
        if #available(macOS 26, *) {
            background { Color.clear.glassEffect(.regular, in: Brand.panel) }
        } else {
            background(.regularMaterial, in: Brand.panel)
        }
    }

    /// A button on a floating bar; `prominent` for the one to choose.
    @ViewBuilder func glassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26, *) {
            if prominent { buttonStyle(.glassProminent).controlSize(.large) } else { buttonStyle(.glass).controlSize(.large) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }
}

extension Brand {
    /// The corners of a box on a page, like the window's own (and the patch's) rather than square.
    static let card = RoundedRectangle(cornerRadius: 14, style: .continuous)
    /// A panel floating just inside the window, its corners following the window's.
    static let panel = RoundedRectangle(cornerRadius: 18, style: .continuous)
    /// A smaller box: a warning, the chosen ride, a map.
    static let note = RoundedRectangle(cornerRadius: 10, style: .continuous)
}
