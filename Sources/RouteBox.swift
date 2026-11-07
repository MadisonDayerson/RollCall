import SwiftUI
import MapKit

/// The ride's route on its page: a still map of the road route from the meeting place through any stops to the
/// destination, with the distance and riding time. Clicking it opens Route. Rides without two places show nothing.
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
        let places = Route.places(meetingPlace: ride.location, notes: ride.notes)
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
                            Text(RoutePlanner.describe(r) + " · " + places.joined(separator: " → "))
                                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Route", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            }
            .task(id: places.joined(separator: "\n") + (scheme == .dark ? "|dark" : "|light")) { await load(places) }
        }
    }

    private func load(_ places: [String]) async {
        let s = model.store.state.settings
        let home = CLLocationCoordinate2D(latitude: s.homeLatitude, longitude: s.homeLongitude)
        if route.value == nil { state.value = .planning }
        guard let planned = await RoutePlanner.plan(places, near: home),
              let img = await RouteMapImage.draw(planned, size: Self.size, dark: scheme == .dark) else {
            state.value = .failed
            return
        }
        route.value = planned
        image.value = img
        state.value = .done
    }
}
