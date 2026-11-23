import Foundation

/// A post from a forum, blog or news feed. Posts aren't events, but many announce one.
struct PostItem: Codable, Equatable {
    var id: String
    var title: String
    var link: String
    var published: Date?
    var text: String
}

/// Words that suggest a post or web event is about motorcycles. Used to keep general
/// listings (Eventbrite, shop blogs) down to rides and bike events.
enum RideWords {
    /// Clearly about motorbikes.
    static let strong = [
        "motorcycle", "motorcycles", "motorcycling", "motorbike", "motorbikes", "moto", "bike night", "bike show",
        "biker", "bikers", "rideout", "ride out", "dice run", "poker run", "toy run", "track day", "harley",
        "harley-davidson", "ducati", "triumph", "yamaha", "kawasaki", "suzuki", "ktm", "bmw motorrad", "royal enfield",
        "husqvarna", "aprilia", "indian motorcycle", "enduro", "motocross", "supermoto", "sidecar", "cafe racer",
        "dirt bike", "adventure riding", "adv ride", "hooligan", "scooter", "vespa", "ulysses", "hog chapter",
    ]
    /// Ride-ish, but also used for cycling, theatre, cruises… only trusted on motorcycle sites.
    static let loose = ["ride", "rides", "riders", "riding", "rally", "run", "cruise", "bikes", "bike", "meet", "breakfast", "camp"]

    static func matches(_ text: String, strict: Bool) -> Bool {
        let t = text.lowercased()
        return (strict ? strong : strong + loose).contains { w in
            t.range(of: "\\b" + NSRegularExpression.escapedPattern(for: w) + "\\b", options: .regularExpression) != nil
        }
    }
}

/// Finds a date, time and address in free text such as an Instagram caption or forum post.
enum TextDetect {
    struct Found {
        var start: Date?
        var hasTime = false
        var address: String?
    }

    /// A date written out in full ("8 November", "Nov 8", "8/11"), as opposed to "Sunday" or "tomorrow".
    static let absoluteDate = #"\d{1,2}(st|nd|rd|th)?\s*(of\s+)?(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)|(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+\d{1,2}\b|\b\d{1,2}/\d{1,2}(/\d{2,4})?\b"#

    /// `absoluteOnly` ignores "Sunday", "tomorrow" and the like. Use it for old messages,
    /// where those words meant a day relative to when the message was sent, not today.
    static func scan(_ text: String, now: Date = Date(), daysAhead: Int = 180, absoluteOnly: Bool = false) -> Found {
        var found = Found()
        guard let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue
                                                | NSTextCheckingResult.CheckingType.address.rawValue) else { return found }
        let ns = text as NSString
        let cal = Calendar.current
        let limit = now.addingTimeInterval(Double(daysAhead) * 86400)
        let today = cal.startOfDay(for: now)
        let timePattern = #"\d\s*(am|pm|a\.m\.|p\.m\.)|\d[:.]\d\d|noon|midday"#

        // The detector often splits "Sunday 8 November, meet 8:30am" into a date and a separate time.
        struct Hit { var date: Date; var range: NSRange; var hasTime: Bool; var timeOnly: Bool; var piece: String }
        var hits: [Hit] = []
        for m in det.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if m.resultType == .date, let d = m.date {
                let piece = ns.substring(with: m.range).lowercased()
                let hasTime = piece.range(of: timePattern, options: .regularExpression) != nil
                let stripped = piece.replacingOccurrences(of: #"a\.m\.|p\.m\.|(?<=\d|\s)(am|pm)\b|\b(at|from|by|noon|midday|onwards)\b|[\d:.\s-]"#,
                                                          with: "", options: .regularExpression)
                let timeOnly = hasTime && stripped.isEmpty
                if absoluteOnly, !timeOnly, piece.range(of: absoluteDate, options: .regularExpression) == nil { continue }
                hits.append(Hit(date: d, range: m.range, hasTime: hasTime, timeOnly: timeOnly, piece: piece))
            } else if m.resultType == .address, found.address == nil {
                found.address = ns.substring(with: m.range).replacingOccurrences(of: "\n", with: ", ")
            }
        }

        /// The time as written. With no am or pm, the detector picks the next such time after the current clock
        /// time (so "8:30" read at 9am becomes 8:30pm); rides start in the daytime, so 1 to 6 means pm and 7 to 12 as written.
        func written(_ hit: Hit) -> (Int, Int) {
            let tc = cal.dateComponents([.hour, .minute], from: hit.date)
            guard hit.piece.range(of: #"am|pm|a\.m\.|p\.m\.|noon|midday"#, options: .regularExpression) == nil,
                  let r = hit.piece.range(of: #"\b(\d{1,2})[:.](\d{2})\b"#, options: .regularExpression) else {
                return (tc.hour ?? 0, tc.minute ?? 0)
            }
            let parts = hit.piece[r].split(whereSeparator: { $0 == ":" || $0 == "." }).compactMap { Int($0) }
            guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return (tc.hour ?? 0, tc.minute ?? 0) }
            let h = parts[0] >= 1 && parts[0] <= 6 ? parts[0] + 12 : parts[0]
            return (h, parts[1])
        }

        var best: (Date, Bool)?
        for h in hits where !h.timeOnly {
            var date = h.date
            var hasTime = h.hasTime
            if hasTime {
                let (hh, mm) = written(h)
                date = cal.date(bySettingHour: hh, minute: mm, second: 0, of: date) ?? date
            } else if let t = hits.first(where: { $0.timeOnly && abs($0.range.location - (h.range.location + h.range.length)) < 60 }) {
                let (hh, mm) = written(t)
                date = cal.date(bySettingHour: hh, minute: mm, second: 0, of: date) ?? date
                hasTime = true
            }
            // A date with no time comes back at noon; keep anything from today on.
            guard date >= (hasTime ? now : today), date <= limit else { continue }
            if best == nil || date < best!.0 { best = (date, hasTime) }
        }
        if let best {
            found.hasTime = best.1
            found.start = best.1 ? best.0 : cal.startOfDay(for: best.0)
        }
        return found
    }

    /// A short title from the first meaningful line of a post.
    static func title(from text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.count > 3 && !$0.hasPrefix("#") && !$0.hasPrefix("@") } ?? ""
        return line.count > 70 ? String(line.prefix(67)) + "…" : line
    }
}
