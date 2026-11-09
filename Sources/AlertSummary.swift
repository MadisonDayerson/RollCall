import Foundation

/// A brief line about the road alerts at one spot, for the map's hover label: written by Apple's on-device model
/// when Apple Intelligence is on (nothing leaves the Mac), otherwise put together from the alerts themselves.
enum AlertSummary {
    /// Summaries already written, by the alerts they cover, so reopening a ride doesn't ask again.
    @MainActor private static var written: [String: String] = [:]

    static let instructions = """
        You write the hover label for road alerts on a motorcyclist's route map. Reply with one plain sentence of \
        at most 12 words saying what riders will meet and on which road. Mention a closure first. Don't copy the \
        alert text, and leave out dates, times, project names and codes. Use only what the alerts say. No lead-in, \
        no quotes, no formatting.
        Example alert: Closures · Planned roadworks · Hume Freeway, Wallan: Road Program activities occurring between \
        02/09/2026 and 31/03/2027. Impact to traffic will be entry ramp closed. Altered speed limit during operation \
        will be 40.
        Example reply: Hume Freeway entry ramp at Wallan closed for roadworks, 40 km/h.
        """

    /// The feed's wording cut down to what matters, so the model has little to copy: dates and times go (the alerts
    /// already match the ride's time) and its set phrases are shortened.
    static func trimmed(_ details: String) -> String {
        var t = details
        for (pattern, short) in [
            (#"\s*(?:occurring\s+)?between \d{1,2}/\d{1,2}/\d{4} and \d{1,2}/\d{1,2}/\d{4}"#, ""),
            (#"\s*during the following times:[^.]*\."#, "."),
            (#"\s+activities\b"#, ""),
            (#"Impact to traffic will be\s+"#, ""),
            (#"\s*Altered speed limit during operation will be Nil"#, ""),
            (#"Altered speed limit during operation will be (\d+)"#, "$1 km/h"),
            (#"\s*and the traffic delay is expected to be ([^.]+)"#, ", delays $1"),
        ] {
            t = t.replacingOccurrences(of: "(?i)" + pattern, with: short, options: .regularExpression)
        }
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// Which alerts a summary is for.
    static func key(_ alerts: [RoadAlerts.Alert]) -> String { alerts.map(\.id).sorted().joined(separator: "|") }

    /// Asks the on-device model for a summary, once per set of alerts. Nil when it's off or says no.
    @MainActor static func write(_ alerts: [RoadAlerts.Alert]) async -> String? {
        let key = key(alerts)
        if let done = written[key] { return done }
        let lines = alerts.sorted { RoadAlerts.rank($0) < RoadAlerts.rank($1) }.prefix(4).map { a in
            a.summary + (a.details.isEmpty ? "" : ": " + trimmed(a.details))
        }
        guard let reply = await AppleModel.ask(instructions: instructions, AppleModel.Input(heading: "Road alerts", lines: lines))?
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"“”*"))),
              !reply.isEmpty, reply.count <= 140, !reply.contains(" · ") else { return nil }
        written[key] = reply
        return reply
    }

    /// Without the model (or when its reply won't do): the most disruptive alert as "Lanes blocked on Montague
    /// Street, South Melbourne", and how many others there are.
    static func plain(_ alerts: [RoadAlerts.Alert]) -> String {
        guard let worst = alerts.min(by: { RoadAlerts.rank($0) < RoadAlerts.rank($1) }) else { return "" }
        let what = worst.impact.isEmpty || worst.impact == "N/A" ? worst.kind : worst.impact
        let road = [worst.road, worst.place].filter { !$0.isEmpty }.joined(separator: ", ")
        let others = Set(alerts.map(\.summary)).count - 1
        return [what, road].filter { !$0.isEmpty }.joined(separator: " on ") + (others > 0 ? " (and \(others) more)" : "")
    }
}
