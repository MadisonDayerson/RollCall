import SwiftUI
import AppKit

// MARK: - Window

struct MainView: View {
    @ObservedObject var model: UIModel

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { model.page }, set: { if let p = $0 { model.page = p } })) {
                // The tag must come last: a badge added after it hides the tag and the row can't be selected.
                Label("Rides", systemImage: "motorcycle")
                    .badge(model.undecidedCount)
                    .tag(UIModel.Page.rides)
                Label("To review", systemImage: "tray")
                    .badge(model.app.openReviews().count + model.app.postsToLookAt().count)
                    .tag(UIModel.Page.review)
                Label("Sources", systemImage: "antenna.radiowaves.left.and.right").tag(UIModel.Page.sources)
                Label("Settings", systemImage: "gearshape").tag(UIModel.Page.settings)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 190)
            .safeAreaInset(edge: .bottom) { Wordmark().padding(.bottom, 14) }
        } detail: {
            switch model.page {
            case .rides: RidesPage(model: model)
            case .review: ReviewPage(model: model)
            case .sources: SourcesPage(model: model)
            case .settings: SettingsPage(model: model)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { Task { await model.app.refresh() } } label: {
                    Label("Check all sources now", systemImage: "arrow.clockwise")
                }
                .help("Check all sources now")
                .disabled(model.app.refreshing)
                Button { model.showAdd = true } label: { Label("Add", systemImage: "plus") }
                    .help("Add a source or a ride")
            }
        }
        .sheet(isPresented: $model.showAdd) { AddSheet(model: model) }
    }
}

/// RollCall's look, taken from its icon: black and white, a thin double frame like a club patch, spaced
/// capitals like the "ROLLCALL" under the logo, and the gothic lettering saved for a few brand moments.
/// Colour is left for meaning (warnings, problems), so the monochrome reads as the brand.
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
        let ink: Color = filled ? Brand.paper : .primary
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
                    .background(Circle().fill(Brand.paper))
                    .offset(x: 5 * scale, y: -5 * scale)
            }
        }
        .opacity(decision == .skip ? 0.5 : past ? 0.7 : 1)
        .accessibilityHidden(true)
    }

    private static func fmt(_ f: String) -> DateFormatter {
        let d = DateFormatter(); d.locale = Locale(identifier: "en_AU"); d.dateFormat = f; return d
    }
    static let month = fmt("MMM"), day = fmt("d"), weekday = fmt("EEE")
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

/// "Roll Call" in the logo's gothic lettering, at the foot of the sidebar.
struct Wordmark: View {
    var body: some View {
        if let img = Brand.wordmark {
            Image(nsImage: img)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 120, maxHeight: 34)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Roll Call")
        }
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
            } else if showingDetail {
                VStack(spacing: 0) {
                    HStack {
                        Button(action: close) { Label(back, systemImage: "chevron.left") }
                            .buttonStyle(.borderless)
                        Spacer()
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    Divider()
                    detail.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                list.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
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
