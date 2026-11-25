import Foundation

/// Regular rides that meet somewhere else depending on the week of the month ("2nd & 4th Thursday: Example Zoo").
/// RollCall works out which week a ride is in from its date and takes that week's meeting place. The places are read
/// from labelled lines, or from looser wording by Apple's on-device model, which can list places and weeks but can't
/// tell which week a date is in.
enum MeetingPlaces {
    /// The weeks of the month in a post: 1 to 5, or `last`.
    static let last = 0

    /// Some weeks named together in a post ("2nd & 4th Thursday").
    struct Weeks: Equatable {
        var weeks: Set<Int>
        /// 1 (Sunday) to 7, or nil when the day isn't repeated ("…, 2nd & 4th: …").
        var weekday: Int?
    }

    struct Rule: Equatable {
        var place: String
        var weeks: Set<Int>
    }

    private static let ordinals = ["1st": 1, "first": 1, "2nd": 2, "second": 2, "3rd": 3, "third": 3,
                                   "4th": 4, "fourth": 4, "5th": 5, "fifth": 5, "last": last]
    private static let names = #"(?:1st|first|2nd|second|3rd|third|4th|fourth|5th|fifth|last)\b"#
    private static let weekday = #"(?:sun(?:day)?|mon(?:day)?|tue(?:s|sday)?|wed(?:s|nesday)?|thu(?:r|rs|rsday)?|fri(?:day)?|sat(?:urday)?)s?\b"#
    /// "1st, 3rd & 5th Thursdays": the weeks, then the day.
    private static let named = #"\b("# + names + #"(?:\s*(?:,|/|&|\+|\band\b)+\s*(?:and\s+|the\s+)?"# + names + #")*)(?:\s+("# + weekday + "))?"

    // MARK: Reading the post

    private static func weeks(_ list: String, day: String?) -> Weeks {
        let found = list.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).compactMap { ordinals[$0] }
        return Weeks(weeks: Set(found), weekday: day.flatMap { RidePlan.weekdays[String($0.lowercased().prefix(3))] })
    }

    /// The weeks a post names. One week on its own has to say its day, so a date ("1st December") isn't one, and
    /// neither is a run of dates.
    static func named(in text: String) -> [Weeks] {
        let re = try! NSRegularExpression(pattern: "(?i)" + named + #"(?!\s+(?:of\s+)?(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec))"#)
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { m in
            guard let list = Range(m.range(at: 1), in: text) else { return nil }
            let w = weeks(String(text[list]), day: Range(m.range(at: 2), in: text).map { String(text[$0]) })
            return w.weekday != nil || w.weeks.count >= 2 ? w : nil
        }
    }

    /// The post names different weeks for the ride's day of the week.
    static func varies(_ ride: RideEvent) -> Bool { !named(for: ride).isEmpty }

    /// The sets of weeks the post tells apart, or none when it doesn't.
    private static func named(for ride: RideEvent) -> [Set<Int>] {
        let day = Calendar.current.component(.weekday, from: ride.start)
        let found = named(in: ride.notes).filter { $0.weekday == nil || $0.weekday == day }
        let sets = found.map(\.weeks).uniqued()
        let apart = sets.contains { a in sets.contains { a.isDisjoint(with: $0) } }
        return apart && found.contains { $0.weekday == day } ? sets : []
    }

    /// The places on labelled lines ("2nd & 4th Thursday: Example Zoo"), under a heading about where it meets.
    static func labelled(in notes: String) -> [Rule] {
        let line = try! NSRegularExpression(pattern: "(?i)^" + named + #"(?:\s+of\s+(?:the|each|every)\s+month)?\s*[:–—-]\s*(.+)$"#)
        let about = #"(?i)\b(?:meet\w*|start\w*|depart\w*|leav\w*|locations?|where)\b"#
        var rules: [Rule] = [], heading = ""
        for raw in notes.components(separatedBy: .newlines) {
            // Skip bullets and emoji.
            let text = String(raw.drop { !$0.isLetter && !$0.isNumber })
            if text.isEmpty { continue }
            guard let m = line.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let list = Range(m.range(at: 1), in: text), let value = Range(m.range(at: 3), in: text) else { heading = text; continue }
            let place = text[value].replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ".,")))
            guard heading.range(of: about, options: .regularExpression) != nil, place.count >= 3 else { continue }
            rules.append(Rule(place: place, weeks: weeks(String(text[list]), day: nil).weeks))
        }
        return rules
    }

    // MARK: Picking the place

    /// The place for the ride's week, when the rules give just one.
    static func pick(_ rules: [Rule], on date: Date) -> String? {
        let cal = Calendar.current
        let day = cal.component(.day, from: date)
        let isLast = day + 7 > cal.range(of: .day, in: .month, for: date)!.count
        let lastPlaces = isLast ? rules.filter { $0.weeks.contains(last) } : []
        let places = (lastPlaces.isEmpty ? rules.filter { $0.weeks.contains(week(of: date)) } : lastPlaces).map(\.place).uniqued()
        return places.count == 1 ? places[0] : nil
    }

    static func week(of date: Date) -> Int { (Calendar.current.component(.day, from: date) - 1) / 7 + 1 }

    /// Rides you typed in yourself keep the place you gave.
    static func applies(to ride: RideEvent) -> Bool { !["manual", "instagram"].contains(ride.source) && varies(ride) }

    /// The ride with its week's meeting place. One read by the model before (`old`) stays while the post and date do.
    static func settled(_ ride: RideEvent, old: RideEvent?) -> RideEvent {
        guard applies(to: ride) else { return ride }
        if let place = pick(labelled(in: ride.notes), on: ride.start) { return ride.meeting(at: place) }
        if let old, old.placeByWeek == true, old.start == ride.start, old.notes == ride.notes { return ride.meeting(at: old.location) }
        return ride
    }

    /// The post gives this place.
    static func says(_ notes: String, _ place: String) -> Bool {
        let p = Brief.letters(place)
        return !p.isEmpty && Brief.letters(notes).contains(p)
    }

    // MARK: Apple's on-device model

    static let instructions = """
        A regular motorbike ride's post says it starts in different places on different weeks of the month. \
        List each meeting place, one per line, in exactly this format and nothing else:
        PLACE: the meeting place, exactly as the post writes it | WEEKS: the numbers of the weeks of the month it is used, such as 1, 3
        """

    /// What the model listed, if every line holds up: the post gives the place, and names those weeks together.
    static func rules(from reply: String, ride: RideEvent) -> [Rule] {
        let sets = named(for: ride)
        var out: [Rule] = []
        for raw in reply.split(whereSeparator: \.isNewline) {
            let parts = raw.replacingOccurrences(of: "**", with: "").components(separatedBy: "|")
            guard parts.count == 2 else { continue }
            let place = parts[0].replacingOccurrences(of: #"(?i)^\W*place:\s*"#, with: "", options: .regularExpression)
                // The model can add the weeks to the place as well.
                .replacingOccurrences(of: #"(?i)[\s,(]*(?:\bon\s+)?(?:the\s+)?"# + named + #"\)?\s*$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            let weeks = Set(parts[1].components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) })
            guard says(ride.notes, place), sets.contains(weeks) else { return [] }
            out.append(Rule(place: place, weeks: weeks))
        }
        return out.count >= 2 ? out : []
    }

    /// What the model listed for each post, so a post is only read once while RollCall is open.
    @MainActor private static var read: [String: [Rule]] = [:]

    @MainActor static func modelRules(for ride: RideEvent) async -> [Rule] {
        if let known = read[ride.notes] { return known }
        guard AppleModel.available, let reply = await AppleModel.ask(instructions: instructions, RideDetails.input(post: ride.notes))
        else { return [] }
        let found = rules(from: reply, ride: ride)
        read[ride.notes] = found
        return found
    }
}

private extension RideEvent {
    /// Its place, to be found on the map again.
    func meeting(at place: String) -> RideEvent {
        var e = self
        e.placeByWeek = true
        guard place != location else { return e }
        e.location = place
        e.latitude = nil; e.longitude = nil; e.distanceKm = nil
        return e
    }
}

extension Store {
    /// Has the model read the meeting places of a source's rides whose posts don't label them plainly. Returns the
    /// rides whose place it found.
    @MainActor
    func readMeetingPlaces(from source: String, now: Date = Date()) async -> [String] {
        var changed: [String] = []
        for ride in state.events.values where ride.source == source && ride.start > now && state.rideEdits[ride.id] == nil {
            guard MeetingPlaces.applies(to: ride), ride.placeByWeek != true,
                  let place = MeetingPlaces.pick(await MeetingPlaces.modelRules(for: ride), on: ride.start),
                  // Changed or removed while the model was reading.
                  let current = state.events[ride.id], state.rideEdits[ride.id] == nil else { continue }
            state.events[ride.id] = current.meeting(at: place)
            changed.append(ride.id)
        }
        return changed
    }

    /// What a ride's page says under its place when its meeting place depends on the week.
    func meetingNote(_ ride: RideEvent) -> String? {
        guard MeetingPlaces.applies(to: ride) else { return nil }
        if ride.placeByWeek == true {
            let week = ["1st", "2nd", "3rd", "4th", "5th"][MeetingPlaces.week(of: ride.start) - 1]
            return "The post's meeting place for the \(week) \(ride.start.formatted(.dateTime.weekday(.wide))) of the month."
        }
        // Your own change to the ride gives the place.
        if state.rideEdits[ride.id] != nil { return nil }
        return "The meeting place depends on the week. Check the post for where to go."
    }
}
