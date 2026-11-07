import Foundation
import CoreLocation

/// The weather along a ride's route: points every 40 to 50 km, each with the time you'd reach it, and the
/// hourly forecast there from Open-Meteo (free, no account). Only the points' positions go online, and nothing
/// is saved to disk.
enum RouteWeather {
    struct Point {
        var spot: CLLocationCoordinate2D
        var km: Double
        var time: Date
    }

    struct Forecast {
        var spot: CLLocationCoordinate2D
        var km: Double
        var time: Date
        var temperature: Double
        var rainChance: Int
        var wind: Double
        var gusts: Double
        var code: Int
    }

    /// Worth a second look on a bike, so shown in orange: likely rain, strong gusts.
    static let rainWarning = 60
    static let gustWarning = 50.0

    /// Forecasts reach a week ahead (today and the next 7 days).
    static let forecastDays = 8
    /// About how far apart the points are.
    static let spacingKm = 45.0
    static let maxPoints = 9

    /// Evenly spaced points from start to finish, each with when you'd get there riding steadily from `leave`.
    static func points(along legs: [[CLLocationCoordinate2D]], seconds: Double, leave: Date) -> [Point] {
        let line = legs.flatMap { $0 }
        guard let first = line.first else { return [] }
        var walked = [0.0]
        for (a, b) in zip(line, line.dropFirst()) {
            walked.append(walked.last! + Store.haversineKm(a.latitude, a.longitude, b.latitude, b.longitude))
        }
        let total = walked.last!
        guard total > 0 else { return [Point(spot: first, km: 0, time: leave)] }
        let gaps = min(max(1, Int((total / spacingKm).rounded())), maxPoints - 1)
        var out: [Point] = []
        var i = 0
        for n in 0...gaps {
            let km = total * Double(n) / Double(gaps)
            while i < walked.count - 1, walked[i + 1] < km { i += 1 }
            out.append(Point(spot: line[i == walked.count - 1 ? i : (km - walked[i] < walked[i + 1] - km ? i : i + 1)],
                             km: km, time: leave.addingTimeInterval(seconds * km / total)))
        }
        return out
    }

    /// Open-Meteo's forecast address for the points: one request for all of them.
    static func url(for points: [Point]) -> URL? {
        func list(_ v: [Double]) -> String { v.map { String(format: "%.3f", $0) }.joined(separator: ",") }
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        c?.queryItems = [
            URLQueryItem(name: "latitude", value: list(points.map(\.spot.latitude))),
            URLQueryItem(name: "longitude", value: list(points.map(\.spot.longitude))),
            URLQueryItem(name: "hourly", value: "temperature_2m,precipitation_probability,wind_speed_10m,wind_gusts_10m,weather_code"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "forecast_days", value: String(forecastDays)),
        ]
        return c?.url
    }

    /// The forecast at each point for the hour nearest when you'd be there. Points outside the forecast's
    /// range are left out. Open-Meteo replies with a list for several points and one object for one.
    static func read(_ data: Data, for points: [Point]) -> [Forecast] {
        struct Reply: Decodable {
            struct Hourly: Decodable {
                var time: [Double]
                var temperature_2m: [Double?]
                var precipitation_probability: [Double?]
                var wind_speed_10m: [Double?]
                var wind_gusts_10m: [Double?]
                var weather_code: [Double?]
            }
            var hourly: Hourly
        }
        let replies = (try? JSONDecoder().decode([Reply].self, from: data))
            ?? (try? JSONDecoder().decode(Reply.self, from: data)).map { [$0] } ?? []
        guard replies.count == points.count else { return [] }
        return zip(points, replies).compactMap { p, r in
            let h = r.hourly, t = p.time.timeIntervalSince1970
            guard let i = h.time.indices.min(by: { abs(h.time[$0] - t) < abs(h.time[$1] - t) }), abs(h.time[i] - t) <= 3600,
                  let temp = h.temperature_2m[safe: i] ?? nil, let rain = h.precipitation_probability[safe: i] ?? nil,
                  let wind = h.wind_speed_10m[safe: i] ?? nil, let code = h.weather_code[safe: i] ?? nil else { return nil }
            return Forecast(spot: p.spot, km: p.km, time: p.time, temperature: temp, rainChance: Int(rain),
                            wind: wind, gusts: (h.wind_gusts_10m[safe: i] ?? nil) ?? wind, code: Int(code))
        }
    }

    private static var fetched: [URL: (at: Date, forecasts: [Forecast])] = [:]

    /// The forecasts along the route, kept for an hour in memory.
    @MainActor
    static func fetch(_ points: [Point], now: Date = Date()) async -> [Forecast]? {
        guard let url = url(for: points) else { return nil }
        if let kept = fetched[url], now.timeIntervalSince(kept.at) < 3600 { return kept.forecasts }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(Web.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, reply) = try? await Net.session.data(for: request),
              (reply as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let forecasts = read(data, for: points)
        fetched[url] = (now, forecasts)
        return forecasts
    }

    /// When a ride is too far off for the forecast: the day it's first ready.
    static func readyDate(leave: Date, now: Date) -> Date? {
        let lastDay = Calendar.current.date(byAdding: .day, value: forecastDays - 1, to: Calendar.current.startOfDay(for: now)) ?? now
        guard leave >= Calendar.current.date(byAdding: .day, value: 1, to: lastDay) ?? now else { return nil }
        return Calendar.current.date(byAdding: .day, value: -(forecastDays - 1), to: Calendar.current.startOfDay(for: leave))
    }

    /// The weather's symbol and word, from the WMO code Open-Meteo gives.
    static func describe(_ code: Int) -> (symbol: String, word: String) {
        switch code {
        case 0: return ("sun.max", "Clear")
        case 1, 2: return ("cloud.sun", "Partly cloudy")
        case 3: return ("cloud", "Cloudy")
        case 45, 48: return ("cloud.fog", "Fog")
        case 51...57: return ("cloud.drizzle", "Drizzle")
        case 65, 67, 82: return ("cloud.heavyrain", "Heavy rain")
        case 61...67, 80...82: return ("cloud.rain", "Rain")
        case 71...77, 85, 86: return ("cloud.snow", "Snow")
        case 95...99: return ("cloud.bolt.rain", "Storms")
        default: return ("cloud", "Cloudy")
        }
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
