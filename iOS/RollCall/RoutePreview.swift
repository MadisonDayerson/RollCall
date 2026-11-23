import SwiftUI
import MapKit

/// The ride's route on its page, as on the Mac: a map in greys of the road route from the meeting place through any
/// stops to the destination (or from your suburb to a one-place ride), with the distance and riding time, the
/// weather along it and road alerts on it (marked on the map too). Tapping the map opens the route in your maps app.
struct RoutePreview: View {
    @Environment(PhoneModel.self) private var model
    let ride: RideEvent
    let open: () -> Void
    @State private var planned: RoutePlanner.Planned?
    @State private var loading = Loading.planning
    @State private var camera = MapCameraPosition.automatic
    @State private var mapSize = CGSize.zero
    /// The part of the map showing, once the map has settled.
    @State private var showing: MKMapRect?
    @StateObject private var alerts = Box(RoadAlertsView.Loading.loading)

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
                        // One row, so the alerts load (and are marked on the map) before they're scrolled to.
                        VStack(alignment: .leading, spacing: 10) {
                            map(planned, places: places).id(key)
                            details(planned, places: places).padding(.horizontal, 12)
                        }
                        .padding(.bottom, 6)
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
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

    /// The distance and riding time, then the weather and road alerts until the ride is over.
    @ViewBuilder private func details(_ p: RoutePlanner.Planned, places: [String]) -> some View {
        let shown = model.state.settings.roadAlertsShown
        let arriving = places.first == model.store.homePlace
        Text(RoutePlanner.describe(p, places: places, notes: ride.notes)).font(.callout).foregroundStyle(.secondary)
        if ride.finish > Date() {
            Divider()
            RouteWeatherView(route: p, ride: ride, places: places, arriving: arriving)
            if shown != .none {
                Divider()
                RoadAlertsView(route: p, ride: ride, arriving: arriving, shown: shown, state: alerts)
            }
        }
    }

    /// The road alerts to mark on the map.
    private var marked: [RoadAlerts.Alert] {
        if model.state.settings.roadAlertsShown != .none, case .found(let roads, _) = alerts.value { return roads.flatMap(\.alerts) }
        return []
    }

    /// The route in the text colour on a grey map, with the start filled in, the destination outlined and the stops
    /// as small rings, as on the Mac.
    private func map(_ p: RoutePlanner.Planned, places: [String]) -> some View {
        Map(position: $camera, interactionModes: []) {
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
        // Fitted again when an iPad window changes shape: left alone, the map keeps its zoom and can cut off the route's ends.
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            let label: CGFloat = 24  // Apple Maps' label, along the bottom.
            guard size.width > 0, size.height > label else { return }
            (mapSize, showing) = (size, nil)
            var rect = p.mapRect(size: CGSize(width: size.width, height: size.height - label))
            rect.size.height *= size.height / (size.height - label)
            camera = .rect(rect)
        }
        .onMapCameraChange(frequency: .onEnd) { showing = $0.rect }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .accessibilityElement()
        .accessibilityLabel("Map of the route from \(places.first ?? "") to \(places.last ?? "")")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the route in your maps app")
        .overlay {
            if let showing, !marked.isEmpty {
                RoadAlertMarks(alerts: marked, route: p.line, size: mapSize) { place in
                    let at = MKMapPoint(place)
                    return CGPoint(x: (at.x - showing.minX) / showing.width * mapSize.width,
                                   y: (at.y - showing.minY) / showing.height * mapSize.height)
                }
            }
        }
    }
}
