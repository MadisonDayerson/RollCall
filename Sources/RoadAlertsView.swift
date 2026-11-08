import SwiftUI
import MapKit

/// Road alerts on a ride's route, under the weather: closures, crashes, hazards and roadworks on the roads you
/// ride, at the time you'd ride them. Road closures are in orange. Alerts happening now show first; booked
/// works follow once they've downloaded.
struct RoadAlertsView: View {
    let route: RoutePlanner.Planned
    let ride: RideEvent
    let arriving: Bool
    @StateObject private var state = Box(Loading.loading)
    @StateObject private var showAll = Box(false)

    enum Loading { case loading, over, noKey, badKey, failed, found([RoadAlerts.Road], stillBooking: Bool) }

    /// Roads shown before Show all.
    private static let first = 5

    private var window: (from: Date, to: Date) { RoadAlerts.riding(ride, seconds: route.seconds, arriving: arriving) }

    var body: some View {
        Group {
            switch state.value {
            case .loading:
                waiting("Checking road alerts…")
            case .over:
                EmptyView()
            case .noKey:
                Text("Add your free road alerts key in Settings to see closures and roadworks on the route.").foregroundStyle(.secondary)
            case .badKey:
                Text("The road alerts key wasn't accepted. Check it in Settings → Road alerts.").foregroundStyle(.secondary)
            case .failed:
                Text("Road alerts couldn't be loaded. They're tried again when you next open the ride.").foregroundStyle(.secondary)
            case .found(let roads, let stillBooking):
                VStack(alignment: .leading, spacing: 8) {
                    if roads.isEmpty && !stillBooking {
                        Label("No road alerts on the route.", systemImage: "checkmark.circle")
                    }
                    let shown = showAll.value ? roads : Array(roads.prefix(Self.first))
                    ForEach(shown.indices, id: \.self) { i in row(shown[i]) }
                    if roads.count > Self.first {
                        Button(showAll.value ? "Show fewer" : "Show all \(roads.count) roads") { showAll.value.toggle() }
                            .buttonStyle(.link)
                    }
                    if stillBooking { waiting("Downloading booked roadworks (a minute or two the first time)…") }
                    Text(LocalizedStringKey("Road data from the [Department of Transport and Planning](https://opendata.transport.vic.gov.au/) (CC BY 4.0)"))
                        .font(.caption).foregroundStyle(.secondary).tint(.secondary)
                }
            }
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
        .task(id: "\(window.from.timeIntervalSince1970)|\(route.metres)") { await load() }
    }

    private func waiting(_ text: String) -> some View {
        HStack(spacing: 8) { ProgressView().controlSize(.small); Text(text).foregroundStyle(.secondary) }
    }

    /// What it is and which road, then the suburbs, then when.
    private func row(_ r: RoadAlerts.Road) -> some View {
        let what = [r.impact, r.kind].filter { !$0.isEmpty }.joined(separator: " · ")
        let places = r.places.count > 3 ? r.places.prefix(2).joined(separator: ", ") + " + \(r.places.count - 2) more"
                                         : r.places.joined(separator: ", ")
        return Label {
            VStack(alignment: .leading, spacing: 2) {
                Text((what.isEmpty ? "" : what + " · ") + r.name).foregroundStyle(r.closesRoad ? Color.orange : Color.primary)
                if !places.isEmpty { Text(places).lineLimit(2) }
                Text(r.planned ? "Booked for the time of your ride" : "Happening now").foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: r.closesRoad ? "xmark.octagon" : r.planned ? "cone" : "exclamationmark.triangle")
                .foregroundStyle(r.closesRoad ? Color.orange : Color.primary)
        }
        .help(r.details)
    }

    private func load() async {
        let (from, to) = window
        guard to > Date() else { state.value = .over; return }
        let line = route.legs.flatMap { leg in let p = leg.points(); return (0..<leg.pointCount).map { p[$0].coordinate } }
        func matching(_ alerts: [RoadAlerts.Alert]) -> [RoadAlerts.Road] {
            RoadAlerts.byRoad(RoadAlerts.on(line, from: from, to: to, alerts: alerts))
        }
        do {
            let live = try await RoadAlerts.fetchLive()
            state.value = .found(matching(live), stillBooking: true)
            let booked = try await RoadAlerts.fetchBooked()
            state.value = .found(matching(live + booked), stillBooking: false)
        } catch RoadAlerts.Failure.noKey {
            state.value = .noKey
        } catch RoadAlerts.Failure.badKey {
            state.value = .badKey
        } catch is CancellationError {
            return
        } catch {
            state.value = .failed
        }
    }
}
