import SwiftUI
import MapKit

/// Road alerts on a ride's route, under the weather: closures, crashes, hazards and roadworks on the roads you
/// ride, at the time you'd ride them, in a drop-down that starts closed. Road closures are in orange. Alerts
/// happening now show first; booked works follow once they've downloaded. The map marks the same alerts.
struct RoadAlertsView: View {
    let route: RoutePlanner.Planned
    let ride: RideEvent
    let arriving: Bool
    /// Shared with the map, which marks the same alerts.
    @ObservedObject var state: Box<Loading>
    @StateObject private var open = Box(false)

    enum Loading { case loading, over, noKey, badKey, failed, found([RoadAlerts.Road], stillBooking: Bool) }

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
                    } else if !roads.isEmpty {
                        heading(roads)
                        if open.value { ForEach(roads.indices, id: \.self) { i in row(roads[i]) } }
                    }
                    if stillBooking { waiting("Downloading booked roadworks (about a minute the first time)…") }
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

    /// "Road alerts on 6 roads · 2 closed", with closures in orange: click to open or close the list. Its own
    /// chevron rather than a DisclosureGroup, whose deep indent pushed the list across the narrow column.
    private func heading(_ roads: [RoadAlerts.Road]) -> some View {
        let closed = roads.filter(\.closesRoad).count
        return Button { open.value.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: open.value ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(width: Self.iconWidth)
                Text("Road alerts on \(roads.count) \(roads.count == 1 ? "road" : "roads")")
                if closed > 0 { Text("· \(closed) closed").foregroundStyle(.orange) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(open.value ? "Hides the list" : "Shows the list")
    }

    /// The chevron and each road's icon share a width, so the text lines up.
    private static let iconWidth: CGFloat = 16

    /// What it is and which road, then the suburbs. Each sits under the heading's text, its icon under the chevron.
    /// Being listed already means it's on at the time of the ride, so that isn't repeated.
    private func row(_ r: RoadAlerts.Road) -> some View {
        let what = [r.impact, r.kind].filter { !$0.isEmpty }.joined(separator: " · ")
        let places = r.places.count > 3 ? r.places.prefix(2).joined(separator: ", ") + " + \(r.places.count - 2) more"
                                         : r.places.joined(separator: ", ")
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: r.closesRoad ? "xmark.octagon" : r.planned ? "cone" : "exclamationmark.triangle")
                .foregroundStyle(r.closesRoad ? Color.orange : Color.primary)
                .frame(width: Self.iconWidth)
            VStack(alignment: .leading, spacing: 2) {
                Text((what.isEmpty ? "" : what + " · ") + r.name).foregroundStyle(r.closesRoad ? Color.orange : Color.primary)
                if !places.isEmpty { Text(places).foregroundStyle(.secondary).lineLimit(2) }
            }
        }
        .accessibilityElement(children: .combine)
        .help(r.details)
    }

    private func load() async {
        let (from, to) = window
        guard to > Date() else { state.value = .over; return }
        state.value = .loading
        let line = route.line
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
