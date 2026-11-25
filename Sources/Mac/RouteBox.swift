import SwiftUI

/// The ride's route on its page: a still map of the road route from the meeting place through any stops to the
/// destination (or from your suburb to a one-place ride), with the distance and riding time, the weather along
/// it and road alerts on it (marked on the map too). Clicking the map opens Route.
struct RouteBox: View {
    let ride: RideEvent
    @ObservedObject var model: UIModel
    @StateObject private var route = Box<RoutePlanner.Planned?>(nil)
    @StateObject private var alerts = Box(RoadAlertsView.Loading.loading)
    @StateObject private var state = Box(Loading.planning)

    enum Loading { case planning, done, failed }

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
                        if let r = route.value {
                            let shown = model.store.state.settings.roadAlertsShown
                            RouteMap(route: r, places: places, alerts: shown == .none ? [] : marked) { model.app.openRoute(ride) }
                                .id(r.key)
                            let arriving = places.first == model.store.homePlace
                            Text(RoutePlanner.describe(r, places: places, notes: ride.notes, arriving: arriving))
                                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Divider()
                            RouteWeatherView(route: r, ride: ride, places: places, arriving: arriving)
                            if shown != .none {
                                Divider()
                                RoadAlertsView(route: r, ride: ride, arriving: arriving, shown: shown, state: alerts)
                            }
                        }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Route", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            }
            .task(id: places.joined(separator: "\n") + (avoidHighways ? "|no highways" : "")) {
                await load(places, avoidHighways: avoidHighways)
            }
        }
    }

    /// The road alerts to mark on the map.
    private var marked: [RoadAlerts.Alert] {
        if case .found(let roads, _) = alerts.value { return roads.flatMap(\.alerts) }
        return []
    }

    private func load(_ places: [String], avoidHighways: Bool) async {
        let home = model.store.homeSpot
        if route.value == nil { state.value = .planning }
        guard let planned = await RoutePlanner.plan(places, near: home, avoidHighways: avoidHighways) else {
            state.value = .failed
            return
        }
        route.value = planned
        state.value = .done
    }
}
