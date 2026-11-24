import SwiftUI

extension View {
    /// Pull down to refresh, with the logo in the space that opens at the top (in place of the usual spinner). It fills
    /// with blue as the sources are checked. `refreshing` is on while the list is held down for it.
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

    /// How far the list is held down while it refreshes.
    private static let held: CGFloat = 60
    /// The space opens above a large title, which is under the bar on an upright iPhone.
    private static let largeTitle: CGFloat = 52

    init(progress: Box<Double?>, refreshing: Binding<Bool>, action: @escaping () async -> Void) {
        self.progress = progress
        _refreshing = refreshing
        self.action = action
        // The logo takes the spinner's place.
        UIRefreshControl.appearance().tintColor = .clear
    }

    func body(content: Content) -> some View {
        let space = firstRow - restingTop
        content
            .refreshable {
                refreshing = true
                await action()
                // Held down long enough to see the logo's glow when it's done.
                try? await Task.sleep(for: .seconds(0.7))
                // It springs back once this returns.
                Task {
                    try? await Task.sleep(for: .seconds(0.5))
                    refreshing = false
                }
            }
            .onScrollGeometryChange(for: [CGFloat].self) { [$0.contentInsets.top, -$0.contentOffset.y] } action: { _, new in
                let top = new[0]
                firstRow = new[1]
                // Pulled far enough, the list is moved down before the refresh starts.
                if !refreshing, firstRow <= top { restingTop = top }
            }
            .overlay(alignment: .top) {
                Wordmark(picture: Image("Wordmark"), progress: progress)
                    .frame(height: max(space, Self.held))
                    .opacity(min(1, max(0, space / Self.held * 2 - 1)))
                    .padding(.top, restingTop - (width == .compact && height == .regular ? Self.largeTitle : 0))
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
            }
    }
}
