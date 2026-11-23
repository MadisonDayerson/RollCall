import SwiftUI
import MapKit

/// The forecast along a ride's route, under its map: for each point, when you'd get there and the place, then
/// the weather, chance of rain and wind. Likely rain and strong gusts are in orange.
struct RouteWeatherView: View {
    let route: RoutePlanner.Planned
    let ride: RideEvent
    let places: [String]
    /// The route is from your suburb to a one-place ride, so you'd arrive at its start time rather than leave then.
    let arriving: Bool
    @StateObject private var state = Box(Loading.loading)

    enum Loading { case loading, over, later(Date), failed, done([(forecast: RouteWeather.Forecast, place: String)]) }

    private var leave: Date { RouteWeather.leave(ride, seconds: route.seconds, arriving: arriving) }

    var body: some View {
        Group {
            switch state.value {
            case .loading:
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Getting the forecast…").foregroundStyle(.secondary) }
            case .over:
                EmptyView()
            case .later(let day):
                Text("The forecast along the route is ready from \(day.formatted(.dateTime.weekday(.wide).day().month(.wide))).")
                    .foregroundStyle(.secondary)
            case .failed:
                Text("The forecast couldn't be loaded. It's tried again when you next open the ride.").foregroundStyle(.secondary)
            case .done(let rows):
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(rows.indices, id: \.self) { i in row(rows[i].forecast, place: rows[i].place) }
                    Text(LocalizedStringKey((ride.allDay ? "No start time given, so leaving at 9 am. " : "")
                                            + "Weather data by [Open-Meteo.com](https://open-meteo.com/)"))
                        .font(.caption).foregroundStyle(.secondary).tint(.secondary)
                }
            }
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
        .task(id: "\(leave.timeIntervalSince1970)|\(route.metres)") { await load() }
    }

    /// When and where, then the weather beneath, so it fits the narrow ride column.
    private func row(_ f: RouteWeather.Forecast, place: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) { time(f); Text(place).lineLimit(1).truncationMode(.middle).help(place) }
            HStack(spacing: 12) { weather(f) }
        }
    }

    private func time(_ f: RouteWeather.Forecast) -> some View {
        Text(f.time.formatted(date: .omitted, time: .shortened)).foregroundStyle(.secondary).monospacedDigit().fixedSize()
    }

    @ViewBuilder private func weather(_ f: RouteWeather.Forecast) -> some View {
        let sky = RouteWeather.describe(f.code)
        let wind = Int(f.wind.rounded()), gusts = Int(f.gusts.rounded())
        Label("\(Int(f.temperature.rounded()))°", systemImage: sky.symbol).monospacedDigit().fixedSize().help(sky.word)
        Label("\(f.rainChance)%", systemImage: "umbrella").monospacedDigit().fixedSize()
            .foregroundStyle(f.rainChance >= RouteWeather.rainWarning ? Color.orange : Color.primary)
            .help("\(f.rainChance)% chance of rain")
        Label(gusts > wind ? "\(wind)–\(gusts) km/h" : "\(wind) km/h", systemImage: "wind").monospacedDigit().fixedSize()
            .foregroundStyle(f.gusts >= RouteWeather.gustWarning ? Color.orange : Color.primary)
            .help(gusts > wind ? "Wind \(wind) km/h, gusting to \(gusts) km/h" : "Wind \(wind) km/h")
    }

    private func load() async {
        let now = Date()
        guard ride.finish > now else { state.value = .over; return }
        if let day = RouteWeather.readyDate(leave: leave, now: now) { state.value = .later(day); return }
        let legs = route.legs.map { leg in let p = leg.points(); return (0..<leg.pointCount).map { p[$0].coordinate } }
        let points = RouteWeather.points(along: legs, seconds: route.seconds, leave: leave)
        guard let forecasts = await RouteWeather.fetch(points, now: now) else { state.value = .failed; return }
        guard !forecasts.isEmpty else { state.value = .over; return }
        var rows: [(forecast: RouteWeather.Forecast, place: String)] = []
        for f in forecasts { rows.append((f, await name(f, total: points.last?.km ?? 0))) }
        state.value = .done(rows)
    }

    private static var names: [String: String] = [:]

    /// The start and finish by the ride's own names; points along the way by suburb (or distance, if unknown).
    private func name(_ f: RouteWeather.Forecast, total: Double) async -> String {
        if f.km == 0, let first = places.first, Route.point(first) == nil { return RideDetails.shortPlace(first) }
        if f.km == total, let last = places.last, Route.point(last) == nil { return RideDetails.shortPlace(last) }
        let key = String(format: "%.2f,%.2f", f.spot.latitude, f.spot.longitude)
        if let known = Self.names[key] { return known }
        let mark = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: f.spot.latitude, longitude: f.spot.longitude)).first
        guard let suburb = mark?.locality ?? mark?.subAdministrativeArea else { return "\(Int(f.km.rounded())) km in" }
        Self.names[key] = suburb
        return suburb
    }
}
