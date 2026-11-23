import Foundation

/// One event as read from an iCalendar (.ics) file, before it becomes a RideEvent.
struct ICSEvent {
    var uid: String
    var title: String
    var start: Date
    var end: Date?
    var allDay: Bool
    var location: String
    var notes: String
    var url: String?
    var latitude: Double?
    var longitude: Double?
    /// Your own reply, where the calendar says (Facebook's: Going or Interested).
    var response: Decision? = nil
}

/// A small iCalendar reader: enough for Meetup, Facebook, Google Calendar and WordPress
/// event exports. Recurring events are expanded within `horizon` days from now.
enum ICSParser {
    static func parse(_ text: String, horizon: Int = 120, now: Date = Date()) -> [ICSEvent] {
        let lines = unfold(text)
        var events: [ICSEvent] = []
        var props: [(name: String, params: [String: String], value: String)] = []
        var inEvent = false
        var depth = 0  // skip nested VALARM blocks

        for line in lines {
            if line == "BEGIN:VEVENT" { inEvent = true; props = []; depth = 0; continue }
            if !inEvent { continue }
            if line.hasPrefix("BEGIN:") { depth += 1; continue }
            if line.hasPrefix("END:") && line != "END:VEVENT" { depth -= 1; continue }
            if line == "END:VEVENT" {
                inEvent = false
                events.append(contentsOf: build(props, horizon: horizon, now: now))
                continue
            }
            if depth > 0 { continue }
            if let p = splitProperty(line) { props.append(p) }
        }
        return events
    }

    // MARK: - Lines and properties

    static func unfold(_ text: String) -> [String] {
        var out: [String] = []
        let normalised = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        for raw in normalised.components(separatedBy: "\n") {
            if (raw.hasPrefix(" ") || raw.hasPrefix("\t")), !out.isEmpty {
                out[out.count - 1] += raw.dropFirst()
            } else if !raw.isEmpty {
                out.append(raw)
            }
        }
        return out
    }

    static func splitProperty(_ line: String) -> (name: String, params: [String: String], value: String)? {
        // The value starts at the first colon that is not inside a quoted parameter.
        var inQuotes = false
        var colon: String.Index?
        for i in line.indices {
            let c = line[i]
            if c == "\"" { inQuotes.toggle() }
            if c == ":" && !inQuotes { colon = i; break }
        }
        guard let colon else { return nil }
        let head = line[..<colon]
        let value = String(line[line.index(after: colon)...])
        let parts = head.split(separator: ";", omittingEmptySubsequences: false)
        guard let name = parts.first else { return nil }
        var params: [String: String] = [:]
        for p in parts.dropFirst() {
            let kv = p.split(separator: "=", maxSplits: 1)
            if kv.count == 2 {
                params[kv[0].uppercased()] = kv[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }
        return (name.uppercased(), params, value)
    }

    static func unescape(_ s: String) -> String {
        var out = ""
        var it = s.makeIterator()
        while let c = it.next() {
            if c == "\\", let n = it.next() {
                switch n {
                case "n", "N": out.append("\n")
                default: out.append(n)  // \, \; \\
                }
            } else {
                out.append(c)
            }
        }
        return out
    }

    // MARK: - Dates

    /// Returns the date and whether it was a date-only (all-day) value.
    static func parseDate(_ value: String, params: [String: String]) -> (Date, Bool)? {
        let v = value.trimmingCharacters(in: .whitespaces)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        if params["VALUE"] == "DATE" || v.count == 8 {
            f.timeZone = TimeZone.current
            f.dateFormat = "yyyyMMdd"
            return f.date(from: String(v.prefix(8))).map { ($0, true) }
        }
        if v.hasSuffix("Z") {
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        } else {
            f.timeZone = params["TZID"].flatMap(timeZone(named:)) ?? TimeZone.current
            f.dateFormat = "yyyyMMdd'T'HHmmss"
        }
        return f.date(from: v).map { ($0, false) }
    }

    static func timeZone(named name: String) -> TimeZone? {
        if let tz = TimeZone(identifier: name) { return tz }
        // Outlook-style names, and anything that mentions an Australian city.
        let windows: [String: String] = [
            "AUS Eastern Standard Time": "Australia/Melbourne",
            "E. Australia Standard Time": "Australia/Brisbane",
            "Cen. Australia Standard Time": "Australia/Adelaide",
            "W. Australia Standard Time": "Australia/Perth",
            "Tasmania Standard Time": "Australia/Hobart",
        ]
        if let id = windows[name] { return TimeZone(identifier: id) }
        for city in ["Melbourne", "Sydney", "Hobart", "Brisbane", "Adelaide", "Perth"] where name.contains(city) {
            return TimeZone(identifier: "Australia/\(city)")
        }
        return nil
    }

    // MARK: - Building events

    static func build(_ props: [(name: String, params: [String: String], value: String)], horizon: Int, now: Date) -> [ICSEvent] {
        func first(_ n: String) -> (params: [String: String], value: String)? {
            props.first { $0.name == n }.map { ($0.params, $0.value) }
        }
        if let status = first("STATUS")?.value, status.uppercased() == "CANCELLED" { return [] }
        guard let ds = first("DTSTART"), let (start, allDay) = parseDate(ds.value, params: ds.params) else { return [] }

        var end: Date?
        if let de = first("DTEND") {
            end = parseDate(de.value, params: de.params)?.0
        } else if let dur = first("DURATION")?.value, let secs = parseDuration(dur) {
            end = start.addingTimeInterval(secs)
        }

        var lat: Double?, lon: Double?
        if let geo = first("GEO")?.value {
            let parts = geo.split(whereSeparator: { $0 == ";" || $0 == "," }).compactMap { Double($0) }
            if parts.count == 2 { lat = parts[0]; lon = parts[1] }
        }

        let uid = first("UID")?.value ?? "\(first("SUMMARY")?.value ?? "event")-\(ds.value)"
        var base = ICSEvent(
            uid: uid,
            title: unescape(first("SUMMARY")?.value ?? "Untitled event"),
            start: start,
            end: end,
            allDay: allDay,
            location: unescape(first("LOCATION")?.value ?? ""),
            notes: unescape(first("DESCRIPTION")?.value ?? ""),
            url: first("URL")?.value,
            latitude: lat,
            longitude: lon
        )
        switch first("PARTSTAT")?.value.uppercased() {
        case "ACCEPTED": base.response = .attending
        case "TENTATIVE": base.response = .maybe
        default: break
        }

        guard let rrule = first("RRULE")?.value else { return [base] }
        let exdates = Set(props.filter { $0.name == "EXDATE" }.flatMap { p in
            p.value.split(separator: ",").compactMap { parseDate(String($0), params: p.params)?.0 }
        })
        let length = end.map { $0.timeIntervalSince(start) }
        let limit = Calendar.current.date(byAdding: .day, value: horizon, to: now) ?? now
        return expand(rrule, start: start, until: limit, after: now.addingTimeInterval(-86400))
            .filter { !exdates.contains($0) }
            .map { occ in
                var e = base
                e.uid = "\(uid)#\(Int(occ.timeIntervalSince1970))"
                e.start = occ
                e.end = length.map { occ.addingTimeInterval($0) }
                return e
            }
    }

    static func parseDuration(_ s: String) -> TimeInterval? {
        // e.g. PT2H30M, P1D
        var total: TimeInterval = 0
        var num = ""
        var inTime = false
        for c in s.uppercased() {
            switch c {
            case "P", "+": continue
            case "-": return nil
            case "T": inTime = true
            case "0"..."9": num.append(c)
            default:
                guard let n = Double(num) else { return nil }
                num = ""
                switch (c, inTime) {
                case ("W", _): total += n * 604800
                case ("D", _): total += n * 86400
                case ("H", true): total += n * 3600
                case ("M", true): total += n * 60
                case ("S", true): total += n
                default: return nil
                }
            }
        }
        return total
    }

    /// Expands the common recurrence rules clubs use: daily, weekly (optionally on several days),
    /// monthly by day-of-month or by "2nd Sunday" style BYDAY, and yearly.
    static func expand(_ rule: String, start: Date, until horizon: Date, after: Date) -> [Date] {
        var parts: [String: String] = [:]
        for p in rule.split(separator: ";") {
            let kv = p.split(separator: "=", maxSplits: 1)
            if kv.count == 2 { parts[kv[0].uppercased()] = String(kv[1]) }
        }
        let cal = Calendar.current
        let interval = max(1, Int(parts["INTERVAL"] ?? "1") ?? 1)
        let count = parts["COUNT"].flatMap { Int($0) }
        var stop = horizon
        if let u = parts["UNTIL"], let (d, _) = parseDate(u, params: [:]) { stop = min(stop, d) }

        let dayCodes = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]
        let byday: [(ord: Int?, weekday: Int)] = (parts["BYDAY"] ?? "").split(separator: ",").compactMap { tok in
            let s = String(tok)
            guard s.count >= 2, let wd = dayCodes[String(s.suffix(2))] else { return nil }
            let ordStr = s.dropLast(2)
            return (ordStr.isEmpty ? nil : Int(ordStr), wd)
        }
        let time = cal.dateComponents([.hour, .minute, .second], from: start)

        var results: [Date] = []
        var produced = 0
        var period = 0
        func accept(_ d: Date) -> Bool {  // returns false when we should stop entirely
            if d < start { return true }
            if d > stop { return false }
            if let c = count, produced >= c { return false }
            produced += 1
            if d >= after { results.append(d) }
            return true
        }

        let freq = parts["FREQ"] ?? ""
        outer: while period < 2000 {
            switch freq {
            case "DAILY":
                guard let d = cal.date(byAdding: .day, value: period * interval, to: start), accept(d) else { break outer }
            case "WEEKLY":
                guard let weekStart = cal.date(byAdding: .day, value: period * interval * 7, to: start) else { break outer }
                if byday.isEmpty {
                    if !accept(weekStart) { break outer }
                } else {
                    let startWd = cal.component(.weekday, from: weekStart)
                    let days = byday.map { ($0.weekday - startWd + 7) % 7 }.sorted()
                    for off in days {
                        guard let d = cal.date(byAdding: .day, value: off, to: weekStart) else { continue }
                        if !accept(d) { break outer }
                    }
                }
            case "MONTHLY":
                guard let monthDate = cal.date(byAdding: .month, value: period * interval, to: start) else { break outer }
                if byday.isEmpty {
                    if !accept(monthDate) { break outer }
                } else {
                    var comps = cal.dateComponents([.year, .month], from: monthDate)
                    comps.hour = time.hour; comps.minute = time.minute; comps.second = time.second
                    var hits: [Date] = []
                    for b in byday {
                        var c = comps
                        c.weekday = b.weekday
                        c.weekdayOrdinal = b.ord ?? 1
                        if let d = cal.date(from: c), cal.component(.month, from: d) == comps.month { hits.append(d) }
                    }
                    for d in hits.sorted() { if !accept(d) { break outer } }
                }
            case "YEARLY":
                guard let d = cal.date(byAdding: .year, value: period * interval, to: start), accept(d) else { break outer }
            default:
                _ = accept(start)
                break outer
            }
            period += 1
        }
        return results
    }
}
