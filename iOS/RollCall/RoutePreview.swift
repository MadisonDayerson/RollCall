import SwiftUI
import MapKit

/// The ride's route on its page, as on the Mac: a map of the road route from the meeting place through any stops to
/// the destination (or from your suburb to a one-place ride), with the distance and riding time. Tapping the map
/// opens the route in your maps app.
struct RoutePreview: View {
    @Environment(PhoneModel.self) private var model
    let ride: RideEvent
    let open: () -> Void
    @State private var planned: RoutePlanner.Planned?
    @State private var loading = Loading.planning

    enum Loading { case planning, done, failed }

    var body: some View {
        let (places, avoidHighways) = model.route(ride)
        if places.count >= 2 {
            let key = places.joined(separator: "\n") + (avoidHighways ? "|no highways" : "")
            Section("Route") {
                switch loading {
                case .planning:
                    HStack(spacing: 8) { ProgressView(); Text("Planning the route…").foregroundStyle(.secondary) }
                        .frame(maxWidth: .infinity, minHeight: 180)
                case .failed:
                    Text("Apple Maps couldn't find a road route between \(places.joined(separator: ", ")).")
                        .foregroundStyle(.secondary)
                case .done:
                    if let planned {
                        map(planned, places: places).id(key)
                        // A route link's stops are map points, so it's described rather than listed.
                        Text(RoutePlanner.describe(planned) + " · " + (Route.link(in: ride.notes) != nil && places.contains { Route.point($0) != nil }
                                                                         ? "the organiser's route" : places.joined(separator: " → ")))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            .task(id: key) {
                if planned == nil { loading = .planning }
                planned = await RoutePlanner.plan(places, near: model.store.homeSpot, avoidHighways: avoidHighways)
                loading = planned == nil ? .failed : .done
            }
        }
    }

    private func map(_ p: RoutePlanner.Planned, places: [String]) -> some View {
        Map(initialPosition: .automatic, interactionModes: []) {
            ForEach(p.legs.indices, id: \.self) { i in
                MapPolyline(p.legs[i]).stroke(.blue, lineWidth: 4)
            }
            ForEach(p.stops.indices, id: \.self) { i in
                if p.named[i] {
                    // Just the place, not its street address, so the pins don't cover the map.
                    let name = i < places.count ? String(places[i].split(separator: ",").first ?? "") : ""
                    Marker(name, systemImage: i == 0 ? "flag" : i == p.stops.count - 1 ? "flag.checkered" : "mappin",
                           coordinate: p.stops[i])
                        .tint(i == 0 ? .green : i == p.stops.count - 1 ? .red : .orange)
                }
            }
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .accessibilityLabel("Map of the route from \(places.first ?? "") to \(places.last ?? "")")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the route in your maps app")
    }
}
