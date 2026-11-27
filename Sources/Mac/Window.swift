import SwiftUI
import AppKit

// MARK: - Window

struct MainView: View {
    @ObservedObject var model: UIModel

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { model.page }, set: { if let p = $0 { model.page = p } })) {
                Label("Home", systemImage: "house").tag(UIModel.Page.home)
                // The tag must come last: a badge added after it hides the tag and the row can't be selected.
                Label("Rides", systemImage: "motorcycle")
                    .badge(model.undecidedCount)
                    .tag(UIModel.Page.rides)
                // Every ride on the page, settled or still being arranged.
                Label("To review", systemImage: "tray")
                    .badge(model.app.possiblePlans().count + model.app.partialPlans().count)
                    .tag(UIModel.Page.review)
                Label("Sources", systemImage: "antenna.radiowaves.left.and.right").tag(UIModel.Page.sources)
                Label("Settings", systemImage: "gearshape").tag(UIModel.Page.settings)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 190)
            .safeAreaInset(edge: .bottom) {
                if let img = Brand.wordmark { Wordmark(picture: Image(nsImage: img), progress: model.app.refreshProgress).padding(.bottom, 14) }
            }
        } detail: {
            Group {
                switch model.page {
                case .home: HomePage(model: model)
                case .rides: RidesPage(model: model)
                case .review: ReviewPage(model: model)
                case .sources: SourcesPage(model: model)
                case .settings: SettingsPage(model: model)
                }
            }
            .clearTopEdge()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { Task { await model.app.refresh() } } label: {
                    // While it checks, the button shows it's working, as Mail's does.
                    if model.app.refreshing {
                        ProgressView().controlSize(.small).accessibilityLabel("Refreshing")
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .help(model.app.refreshing ? "Checking your sources…"
                      : AppleModel.available ? "Check all sources now, then look for more details about the rides you're going to and plans to review"
                      : "Check all sources now")
                .disabled(model.app.refreshing)
                Menu {
                    Button("Add a Ride…") { model.adding = .ride }
                    Button("Add a Source…") { model.adding = .source }
                } label: { Label("Add", systemImage: "plus") }
                    .help("Add a ride or a source")
            }
        }
        .sheet(item: $model.adding) { AddSheet(model: model, kind: $0) }
    }
}

/// RollCall's look, taken from its icon: black and white, a thin double frame like a club patch, spaced
/// capitals like the "ROLLCALL" under the logo, and the gothic lettering saved for a few brand moments.
/// Colour is left for meaning (warnings, problems) and the wordmark's blue glow while checking (see `Wordmark`),
/// so the monochrome reads as the brand.
enum Brand {
    /// Gothic lettering drawn by Design/make_wordmark.swift. It's a picture of the letters (the font itself
    /// isn't shipped), drawn black and tinted like the text around it, so it follows light and dark mode.
    static func gothic(_ name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"), let img = NSImage(contentsOf: url) else { return nil }
        img.isTemplate = true
        return img
    }
    static let wordmark = gothic("Wordmark")
    static let monogram = gothic("Monogram")
    /// What the window's text sits on, for lettering cut out of a filled patch.
    static let paper = Color(nsColor: .windowBackgroundColor)
}

/// An empty page: the gothic "RC" with a line of help underneath.
struct EmptyState: View {
    let text: String
    var detail: String? = nil

    var body: some View {
        VStack(spacing: 14) {
            if let img = Brand.monogram {
                Image(nsImage: img).renderingMode(.template).resizable().scaledToFit()
                    .frame(height: 46).foregroundStyle(.quaternary).accessibilityHidden(true)
            }
            VStack(spacing: 6) {
                Text(text)
                if let detail { Text(detail).font(.callout) }
            }
            .foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Layout

/// A list beside its details when there's room. In a narrow window (a quarter of the screen, say)
/// the list fills the window and choosing an item shows its details with a Back button.
struct ListAndDetail<ListContent: View, Detail: View>: View {
    var showingDetail: Bool
    var back: String
    var close: () -> Void
    @ViewBuilder var list: ListContent
    @ViewBuilder var detail: Detail
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Below this width the two columns would be cramped.
    static var sideBySide: CGFloat { 600 }

    var body: some View {
        GeometryReader { g in
            if g.size.width >= Self.sideBySide {
                // The details get the larger share: the list starts at about 40% and can't be dragged past
                // half, so the details always have room for their buttons.
                HSplitView {
                    list.frame(minWidth: 250, idealWidth: max(250, g.size.width * 0.4), maxWidth: max(250, g.size.width * 0.5))
                    detail.frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                // The details slide in from the right over the list, like a drawer, and slide back out with
                // Back, so it's clear the list is still there underneath.
                ZStack(alignment: .trailing) {
                    list.frame(maxWidth: .infinity, maxHeight: .infinity)
                    if showingDetail {
                        Color.black.opacity(0.12)
                            .ignoresSafeArea(edges: .top)
                            .contentShape(Rectangle())
                            .onTapGesture(perform: close)
                            .accessibilityHidden(true)  // Back does the same
                            .transition(.opacity)
                        drawer
                            .frame(width: max(g.size.width - 36, 0))
                            .padding([.trailing, .bottom], 8)
                            // With Reduce Motion on, it fades in instead of sliding.
                            .transition(reduceMotion ? .opacity : .move(edge: .trailing))
                    }
                }
                .animation(.spring(response: 0.32, dampingFraction: 0.9), value: showingDetail)
            }
        }
    }

    private var drawer: some View {
        detail.frame(maxWidth: .infinity, maxHeight: .infinity)
            .floatingBar(.top) {
                HStack {
                    Button(action: close) { Label(back, systemImage: "chevron.left") }
                        .glassButton()
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                }
                .padding(10)
                .background(Brand.paper)  // or the list behind the drawer would show faintly through the bar
            }
            .clipShape(Brand.panel)
            // A fine edge, which sets it apart in dark mode, where the shadow doesn't show.
            .overlay(Brand.panel.strokeBorder(Color.primary.opacity(0.12)).allowsHitTesting(false))
            // The shadow is the panel's own, not its text's.
            .background(Brand.panel.fill(Brand.paper).shadow(color: .black.opacity(0.22), radius: 12, y: 3))
    }
}

/// Lays buttons out in rows, wrapping onto the next row when the window is narrow.
struct Flow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: rows.map(\.width).max() ?? 0, height: rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows = [Row()]
        for (i, v) in subviews.enumerated() {
            let size = v.sizeThatFits(.unspecified)
            if !rows[rows.count - 1].items.isEmpty, rows[rows.count - 1].width + spacing + size.width > width { rows.append(Row()) }
            var r = rows[rows.count - 1]
            r.width += (r.items.isEmpty ? 0 : spacing) + size.width
            r.height = max(r.height, size.height)
            r.items.append(i)
            rows[rows.count - 1] = r
        }
        return rows
    }
}
