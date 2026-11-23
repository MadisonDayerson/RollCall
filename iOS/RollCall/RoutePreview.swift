import SwiftUI
import MapKit

/// The ride's route on its page, as on the Mac: a map in greys of the road route from the meeting place through any
/// stops to the destination (or from your suburb to a one-place ride), with the distance and riding time. Tapping
/// the map opens the route in your maps app.
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
            Section {
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
                        Text(RoutePlanner.describe(planned, places: places, notes: ride.notes))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            } header: {
                PatchLabel(text: "Route")
            }
            .task(id: key) {
                if planned == nil { loading = .planning }
                planned = await RoutePlanner.plan(places, near: model.store.homeSpot, avoidHighways: avoidHighways)
                loading = planned == nil ? .failed : .done
            }
        }
    }

    /// The route in the text colour on a grey map, with the start filled in, the destination outlined and the stops
    /// as small rings, as on the Mac.
    private func map(_ p: RoutePlanner.Planned, places: [String]) -> some View {
        Map(initialPosition: .automatic, interactionModes: []) {
            ForEach(p.legs.indices, id: \.self) { i in
                MapPolyline(p.legs[i]).stroke(.primary, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
            ForEach(p.stops.indices, id: \.self) { i in
                let end = i == 0 || i == p.stops.count - 1
                if end || p.named[i] {
                    Annotation("", coordinate: p.stops[i]) {
                        Circle().fill(i == 0 ? Color.primary : DateBadge.paper)
                            .stroke(.primary, lineWidth: 2.5)
                            .frame(width: end ? 12 : 7, height: end ? 12 : 7)
                    }
                }
            }
        }
        .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
        .saturation(0)
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .accessibilityElement()
        .accessibilityLabel("Map of the route from \(places.first ?? "") to \(places.last ?? "")")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the route in your maps app")
    }
}
