import SwiftUI

/// The still map of a ride's route, as wide as the page allows. It's drawn again when its size changes, so a bigger
/// map shows more detail rather than the same picture stretched. Road alerts are marked on it; clicking it opens Route.
struct RouteMap: View {
    let route: RoutePlanner.Planned
    let places: [String]
    let alerts: [RoadAlerts.Alert]
    let open: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var scale
    @StateObject private var size = Box(CGSize.zero)
    @StateObject private var map = Box<RouteMapImage.Drawn?>(nil)
    @StateObject private var failed = Box(false)

    var body: some View {
        Color.clear
            .aspectRatio(480 / 260, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGSize.self) { CGSize(width: $0.size.width.rounded(), height: $0.size.height.rounded()) } action: { size.value = $0 }
            .overlay { content }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .task(id: "\(size.value)|\(scale)|\(scheme)") { await draw() }
    }

    @ViewBuilder private var content: some View {
        if let map = map.value {
            Image(nsImage: map.image).resizable()
                .onTapGesture(perform: open)
                .help("Open the route in your maps app")
                .accessibilityLabel("Map of the route from \(places.first ?? "") to \(places.last ?? "")")
                .overlay { if !alerts.isEmpty { RoadAlertMarks(alerts: alerts, route: route.line, map: map) } }
        } else if failed.value {
            Text("The map couldn't be loaded. Check your internet connection.").font(.callout).foregroundStyle(.secondary)
        } else {
            ProgressView().controlSize(.small).accessibilityLabel("Loading the map")
        }
    }

    private func draw() async {
        guard size.value.width > 0, size.value.height > 0 else { return }
        // While the window is being resized the last picture stretches; a new one is drawn once it settles.
        if map.value != nil { try? await Task.sleep(nanoseconds: 250_000_000) }
        guard !Task.isCancelled else { return }
        let drawn = await RouteMapImage.draw(route, size: size.value, scale: scale, dark: scheme == .dark)
        guard !Task.isCancelled else { return }
        if let drawn { map.value = drawn }
        failed.value = drawn == nil
    }
}
