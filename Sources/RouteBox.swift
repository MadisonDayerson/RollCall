import SwiftUI
import MapKit

/// The ride's route on its page: a still map of the road route from the meeting place through any stops to the
/// destination (or from your suburb to a one-place ride), with the distance and riding time, the weather along
/// it and road alerts on it. Clicking the map opens Route.
struct RouteBox: View {
    let ride: RideEvent
    @ObservedObject var model: UIModel
    @Environment(\.colorScheme) private var scheme
    @StateObject private var route = Box<RoutePlanner.Planned?>(nil)
    @StateObject private var image = Box<NSImage?>(nil)
    @StateObject private var state = Box(Loading.planning)

    enum Loading { case planning, done, failed }

    private static let size = CGSize(width: 480, height: 260)

    var body: some View {
        let (places, avoidHighways) = model.store.route(ride)
        // Work out the start, stops and destination from the description; the map updates once they're found.
        Color.clear.frame(height: 0)
            .task(id: Route.fingerprint(ride)) { await model.app.findRoute(for: ride) }
        if places.count >= 2 {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    switch state.value {
                    case .planning:
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Planning the route…").foregroundStyle(.secondary) }
                            .frame(maxWidth: .infinity, minHeight: 120)
                    case .failed:
                        Text("Apple Maps couldn't find a road route between \(places.joined(separator: ", ")). Check the places with Edit….")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    case .done:
                        if let img = image.value {
                            Image(nsImage: img).resizable().scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .onTapGesture { model.app.openRoute(ride) }
                                .help("Open the route in your maps app")
                                .accessibilityLabel("Map of the route from \(places.first ?? "") to \(places.last ?? "")")
                        }
                        if let r = route.value {
                            // A route link's stops are map points, so it's described rather than listed.
                            Text(RoutePlanner.describe(r) + " · " + (Route.link(in: ride.notes) != nil && places.contains { Route.point($0) != nil }
                                                                     ? "the organiser's route" : places.joined(separator: " → ")))
                                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Divider()
                            RouteWeatherView(route: r, ride: ride, places: places, arriving: places.first == model.store.homePlace)
                            Divider()
                            RoadAlertsView(route: r, ride: ride, arriving: places.first == model.store.homePlace)
                        }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Route", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            }
            .task(id: places.joined(separator: "\n") + (avoidHighways ? "|no highways" : "") + (scheme == .dark ? "|dark" : "|light")) {
                await load(places, avoidHighways: avoidHighways)
            }
        }
    }

    private func load(_ places: [String], avoidHighways: Bool) async {
        let s = model.store.state.settings
        let home = CLLocationCoordinate2D(latitude: s.homeLatitude, longitude: s.homeLongitude)
        if route.value == nil { state.value = .planning }
        guard let planned = await RoutePlanner.plan(places, near: home, avoidHighways: avoidHighways),
              let img = await RouteMapImage.draw(planned, size: Self.size, dark: scheme == .dark) else {
            state.value = .failed
            return
        }
        route.value = planned
        image.value = img
        state.value = .done
    }
}
