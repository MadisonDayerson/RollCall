import Foundation

/// Reads a ride's details out of a conversation or post with Apple's on-device model, for the Add ride form.
/// Runs only when you click Add ride… (you've confirmed it's a ride), and nothing leaves the Mac.
enum RideDetails {
    struct Details: Equatable {
        var title: String?
        var start: Date?
        var hasTime = false
        var hours: Double?
        var meet: String?
        var destination: String?
        var stops: [String] = []
        var link: String?
        var details: String?

        /// The Notes box: the plan in a sentence or two, then the destination and stops on labelled lines,
        /// which Route and the ride's summary read.
        var notes: String {
            var lines: [String] = []
            if let details { lines.append(details) }
            if !stops.isEmpty { lines.append("Stops: " + stops.joined(separator: "; ")) }
            if let destination { lines.append("Destination: " + destination) }
            return lines.joined(separator: "\n")
        }
    }

    static func instructions(now: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_AU")
        f.dateFormat = "EEEE d MMMM yyyy, h:mm a"
        return """
        You fill in a form for a motorcyclist adding a group ride or motorbike event to their calendar. \
        Group chats and posts are casual: slang, swearing, jokes and typos are normal, and words left out show as "…". \
        Today is \(f.string(from: now)). The text is a chat conversation or an event post, and the person has \
        confirmed it describes a ride. Use the time each message was sent to work out what "tomorrow" or "Sunday" meant. \
        Only use what the text says. Never invent a place, time or link: write unknown instead. \
        Reply in exactly this format, one item per line:
        TITLE: a short, clear name for the ride or event in 2 to 7 words, in normal capitals (not all capitals), without dates, never named after a person
        START: when it starts or when people meet, as YYYY-MM-DD HH:MM in 24-hour time, or YYYY-MM-DD if no time was given, or unknown
        END: when it finishes, as YYYY-MM-DD HH:MM, or unknown
        MEET: the meeting point or starting address, or unknown
        DESTINATION: where the ride goes or ends, or unknown
        STOPS: stops on the way, separated by semicolons, or none
        LINK: a web link for the event or route that appears in the text, or unknown
        DETAILS: one to three plain sentences a rider needs: what it is, what to bring, cost, rules. No names of people.
        """
    }

    /// A chat ride named after where it goes: "Yarra Glen to Sugarloaf Reservoir", "Ride to Sugarloaf Reservoir"
    /// or "Ride from Yarra Glen". Nil when the messages named neither end.
    static func routeTitle(from meet: String?, to destination: String?) -> String? {
        switch (meet.map(shortPlace), destination.map(shortPlace)) {
        case let (a?, b?) where a.lowercased() != b.lowercased(): return "\(a) to \(b)"
        case let (_, b?): return "Ride to \(b)"
        case let (a?, nil): return "Ride from \(a)"
        default: return nil
        }
    }

    /// The name of a place without its street number, state or postcode: "12 Example St, Sunshine VIC 3020"
    /// → "Sunshine", "Sugarloaf Reservoir, Christmas Hills" → "Sugarloaf Reservoir".
    static func shortPlace(_ place: String) -> String {
        let parts = place.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard var name = parts.first else { return place }
        if name.first?.isNumber == true, parts.count > 1 { name = parts[1] }
        name = name.replacingOccurrences(of: #"\s+(VIC|NSW|QLD|SA|WA|TAS|NT|ACT)\b.*$|\s+\d{4}$"#, with: "", options: .regularExpression)
        return name.isEmpty ? place : name
    }

    /// The text to read: a conversation's messages with when each was sent, or a post as it is.
    static func input(_ lines: [ChatLine], chatName: String) -> AppleModel.Input { PlanSummariser.input(lines, chatName: chatName) }
    static func input(post: String) -> AppleModel.Input { AppleModel.Input(heading: "Event post", lines: [post]) }

    static func extract(_ input: AppleModel.Input, now: Date = Date()) async -> Details? {
        guard let reply = await AppleModel.ask(instructions: instructions(now: now), input),
              var d = parse(reply, now: now) else { return nil }
        // Only a link the text really has, as it was written (the model reads links shortened).
        d.link = d.link.flatMap { AppleModel.originalLink($0, in: input.text) }
        return d
    }

    /// Reads the model's reply. Returns nil if it didn't follow the format.
    static func parse(_ reply: String, now: Date) -> Details? {
        var fields: [String: String] = [:]
        for raw in reply.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "**", with: "")
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-•*"))).uppercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if ["TITLE", "START", "END", "MEET", "DESTINATION", "STOPS", "LINK", "DETAILS"].contains(key) { fields[key] = value }
        }
        guard !fields.isEmpty else { return nil }
        func known(_ key: String) -> String? {
            guard let v = fields[key]?.trimmingCharacters(in: CharacterSet(charactersIn: " \"")), !v.isEmpty,
                  !["unknown", "none", "nothing", "n/a", "not specified", "not given", "unclear", "tbc", "tba"]
                    .contains(v.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))) else { return nil }
            return v
        }
        func date(_ key: String) -> (Date, Bool)? {
            guard let v = known(key) else { return nil }
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            for (pattern, timed) in [("yyyy-MM-dd HH:mm", true), ("yyyy-MM-dd", false)] {
                f.dateFormat = pattern
                // Only trust dates that make sense: not long past, not far off.
                if let d = f.date(from: v), d > now.addingTimeInterval(-2 * 86400), d < now.addingTimeInterval(366 * 86400) { return (d, timed) }
            }
            return nil
        }
        var d = Details()
        d.title = known("TITLE").map { t in
            // The small model sometimes shouts back an all-caps title.
            t == t.uppercased() && t.count > 4 ? Brief.plainValue(t).capitalizedFirst : t
        }
        if let (start, timed) = date("START") {
            d.start = start; d.hasTime = timed
            if timed, let (end, endTimed) = date("END"), endTimed, end > start, end.timeIntervalSince(start) <= 24 * 3600 {
                d.hours = (end.timeIntervalSince(start) / 1800).rounded() / 2  // to the half hour
            }
        }
        d.meet = known("MEET").flatMap { vagueArea($0) ? nil : $0 }
        d.destination = known("DESTINATION").flatMap { vagueArea($0) ? nil : $0 }
        d.stops = known("STOPS").map { $0.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } } ?? []
        // Only a link the text really has: the model must not make one up.
        d.link = known("LINK").flatMap { l in l.range(of: #"^https?://\S+$"#, options: .regularExpression) != nil ? l : nil }
        d.details = known("DETAILS")
        return d
    }
}
