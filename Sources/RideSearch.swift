import Foundation

/// Finding more about one ride: text from its event page, other listings, posts and chats that might be about it
/// is read by Apple's on-device model, which must agree it's about this very ride (the same event, the same day)
/// before anything is offered. Only details the ride doesn't have yet are offered, and only you add them.
enum RideSearch {
    /// Text that might be about the ride, and where it came from.
    struct Clue {
        var from: String
        var input: AppleModel.Input
    }

    /// A detail the ride doesn't have yet.
    struct Finding: Equatable, Identifiable {
        enum Field: String { case time, place, destination, stops, details, link }
        var field: Field
        var value: String
        var from: String
        /// For a time: the new start and end.
        var start: Date? = nil
        var end: Date? = nil

        var id: String { field.rawValue + ":" + value }
        var label: String {
            switch field {
            case .time: return "Time"
            case .place: return "Meet at"
            case .destination: return "Going to"
            case .stops: return "Stops"
            case .details: return "Details"
            case .link: return "Link"
            }
        }
    }

    private static let dayWords: Set<String> = [
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "mon", "tue", "wed", "thu", "fri", "sat", "sun",
        "today", "tomorrow", "tonight", "morning", "afternoon", "evening", "night", "weekend",
        "january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december",
    ]

    /// A quick sift before the model reads anything: the text shares the ride's name (two of its words, or its
    /// only one) or names its meeting place. Day names don't count: every Sunday ride has those.
    static func mightBeAbout(_ text: String, _ ride: RideEvent) -> Bool {
        let words = CrossPost.words(text)
        let name = CrossPost.words(ride.title).subtracting(dayWords)
        if !name.isEmpty, name.intersection(words).count >= min(2, name.count) { return true }
        let place = CrossPost.words(RideDetails.shortPlace(ride.location)).subtracting(dayWords)
        return !place.isEmpty && place.isSubset(of: words)
    }

    /// The messages that might be about the ride, each with the three after it (where replies settle things).
    static func aboutRide(_ lines: [ChatLine], _ ride: RideEvent) -> [ChatLine] {
        var keep = IndexSet()
        for (i, l) in lines.enumerated() where RideSearch.mightBeAbout(l.text, ride) {
            keep.insert(integersIn: i..<min(i + 4, lines.count))
        }
        return Array(keep.map { lines[$0] }.suffix(PlanFinder.maxLines))
    }

    static func instructions(for ride: RideEvent, now: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_AU")
        f.dateFormat = ride.allDay ? "EEEE d MMMM yyyy" : "EEEE d MMMM yyyy, h:mm a"
        let today = DateFormatter()
        today.locale = Locale(identifier: "en_AU")
        today.dateFormat = "EEEE d MMMM yyyy"
        let place = ride.location.isEmpty ? "place not known yet" : ride.location
        return """
        You check whether some text is about one particular motorbike ride or event, for a rider. Chats and posts are \
        casual: slang, jokes and typos are normal. Today is \(today.string(from: now)). Use the time each message was \
        sent to work out what "tomorrow" or "Sunday" meant.
        The ride: "\(ride.title)", \(f.string(from: ride.start)), \(place).
        SAME is yes only if the text is clearly about this same ride or event, on the same day. A different ride, the \
        same ride another week, or general chat is no. If you're unsure, it's no.
        Only use what the text says about this ride. Never invent a place, time or link: write unknown instead.
        Reply in exactly this format, one item per line:
        SAME: yes or no
        START: when it starts or when people meet, as YYYY-MM-DD HH:MM in 24-hour time, or unknown
        END: when it finishes, as YYYY-MM-DD HH:MM, or unknown
        MEET: the meeting point or starting address, or unknown
        DESTINATION: where the ride goes or ends, or unknown
        STOPS: stops on the way, separated by semicolons, or none
        LINK: a web link for the event or route that appears in the text, or unknown
        DETAILS: one or two plain sentences of what a rider needs to know: cost, what to bring, rules, changes. No names of people. Or unknown
        """
    }

    /// The model said the text is about this ride.
    static func same(_ reply: String) -> Bool {
        for raw in reply.split(whereSeparator: \.isNewline) {
            let line = raw.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces)
            guard line.uppercased().hasPrefix("SAME:") else { continue }
            return line.dropFirst(5).trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("yes")
        }
        return false
    }

    /// What the text says about the ride, or nil when the model doesn't agree it's this ride.
    static func verify(_ clue: Clue, ride: RideEvent, now: Date = Date()) async -> RideDetails.Details? {
        guard let reply = await AppleModel.ask(instructions: instructions(for: ride, now: now), clue.input) else { return nil }
        return read(reply, ride: ride, original: clue.input.text, now: now)
    }

    static func read(_ reply: String, ride: RideEvent, original: String, now: Date) -> RideDetails.Details? {
        guard same(reply), var d = RideDetails.parse(reply, now: now) else { return nil }
        // A time on another day is another ride, whatever the model said.
        if let s = d.start, !Calendar.current.isDate(s, inSameDayAs: ride.start) { return nil }
        d.link = d.link.flatMap { AppleModel.originalLink($0, in: original) }
        return d
    }

    /// The details found that the ride doesn't already have.
    static func findings(_ d: RideDetails.Details, for ride: RideEvent, from: String) -> [Finding] {
        func known(_ s: String) -> Bool {
            let w = CrossPost.words(s)
            return !w.isEmpty && CrossPost.overlap(w, CrossPost.words(ride.location + " " + ride.notes + " " + ride.title)) >= 0.75
        }
        var out: [Finding] = []
        if let s = d.start, d.hasTime, ride.allDay || abs(s.timeIntervalSince(ride.start)) >= 60 {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_AU")
            f.dateFormat = "h:mm a"
            let end = d.hours.map { s.addingTimeInterval($0 * 3600) }
            let value = f.string(from: s).lowercased() + (end.map { " – " + f.string(from: $0).lowercased() } ?? "")
            out.append(Finding(field: .time, value: value, from: from, start: s, end: end))
        }
        if let m = d.meet, !known(m) { out.append(Finding(field: .place, value: m, from: from)) }
        if let dest = d.destination, !known(dest) { out.append(Finding(field: .destination, value: dest, from: from)) }
        let stops = d.stops.filter { !known($0) }
        if !stops.isEmpty { out.append(Finding(field: .stops, value: stops.joined(separator: "; "), from: from)) }
        if let more = d.details, !known(more) { out.append(Finding(field: .details, value: more, from: from)) }
        if ride.url == nil, let l = d.link { out.append(Finding(field: .link, value: l, from: from)) }
        return out
    }

    /// The ride with a finding added, as your own change.
    static func edit(_ ride: RideEvent, adding f: Finding) -> RideEdit {
        var e = RideEdit(title: ride.title, start: ride.start, end: ride.end, allDay: ride.allDay,
                         location: ride.location, notes: ride.notes, url: ride.url)
        func addLine(_ line: String) { e.notes = e.notes.isEmpty ? line : e.notes + "\n" + line }
        switch f.field {
        case .time:
            guard let s = f.start else { break }
            let length = ride.allDay ? 3 * 3600 : (ride.end ?? ride.start.addingTimeInterval(3 * 3600)).timeIntervalSince(ride.start)
            e.start = s; e.end = f.end ?? s.addingTimeInterval(length); e.allDay = false
        case .place: e.location = f.value
        case .destination: addLine("Destination: " + f.value)
        case .stops: addLine("Stops: " + f.value)
        case .details: addLine(f.value + " (from \(f.from))")
        case .link: e.url = f.value
        }
        return e
    }
}
