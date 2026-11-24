import SwiftUI

extension View {
    /// Pull down to refresh, with the logo in the space that opens at the top (in place of the usual spinner). It's grey
    /// until the pull is long enough to refresh, then fills with blue as the sources are checked. `refreshing` is on while
    /// the list is held down for it.
    func pullToRefresh(progress: Box<Double?>, refreshing: Binding<Bool>, _ action: @escaping () async -> Void) -> some View {
        modifier(PullToRefresh(progress: progress, refreshing: refreshing, action: action))
    }
}

private struct PullToRefresh: ViewModifier {
    let progress: Box<Double?>
    @Binding var refreshing: Bool
    let action: () async -> Void
    /// Where the list starts below the bar when it isn't pulled down.
    @State private var restingTop: CGFloat = 0
    /// Where its first row is.
    @State private var firstRow: CGFloat = 0
    @Environment(\.horizontalSizeClass) private var width
    @Environment(\.verticalSizeClass) private var height

    /// Keeps the logo grey on a pull too short to refresh, even if a check is already going.
    private static let unlit = Box<Double?>(nil)
    /// How far the list is held down while it refreshes.
    private static let held: CGFloat = 60
    /// The space opens above a large title, which is under the bar on an upright iPhone. The bar is empty then, so the
    /// logo has its room too.
    private static let largeTitle: CGFloat = 52, bar: CGFloat = 44

    init(progress: Box<Double?>, refreshing: Binding<Bool>, action: @escaping () async -> Void) {
        self.progress = progress
        _refreshing = refreshing
        self.action = action
        // The logo takes the spinner's place.
        UIRefreshControl.appearance().tintColor = .clear
    }

    func body(content: Content) -> some View {
        let space = firstRow - restingTop
        let largeTitle = width == .compact && height == .regular
        content
            .refreshable {
                refreshing = true
                // In a task of its own: SwiftUI cancels this one when the page redraws, which checking makes it do.
                await Task {
                    await action()
                    // A check that was already going is followed to its end.
                    while progress.value != nil { try? await Task.sleep(for: .seconds(0.2)) }
                    // Held down long enough to see the logo's glow when it's done.
                    try? await Task.sleep(for: .seconds(0.7))
                }.value
                // It springs back once this returns.
                Task {
                    try? await Task.sleep(for: .seconds(0.5))
                    refreshing = false
                }
            }
            .onScrollGeometryChange(for: [CGFloat].self) { [$0.contentInsets.top, -$0.contentOffset.y] } action: { _, new in
                let top = new[0]
                firstRow = new[1]
                // Pulled far enough, the list is moved down before the refresh starts. A smaller change is the large title
                // opening, when the pull starts with the list scrolled.
                if !refreshing, firstRow <= top || top < restingTop + Self.held - 1 { restingTop = top }
            }
            .overlay(alignment: .top) {
                Wordmark(picture: Image("Wordmark"), progress: refreshing ? progress : Self.unlit, width: 200)
                    .frame(height: max(space, Self.held) + (largeTitle ? Self.bar : 0))
                    // Once there's nearly room for it above the title.
                    .opacity(min(1, max(0, space / Self.held * 3 - 2)))
                    .padding(.top, restingTop - (largeTitle ? Self.largeTitle + Self.bar : 0))
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
            }
    }
}
