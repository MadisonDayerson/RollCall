import Foundation
import FoundationModels

/// One chat message, kept with a possible plan so the conversation can be shown and summarised.
struct ChatLine: Codable, Equatable {
    var id: String
    var sender: String
    var sent: Date
    var text: String
    /// Says a time, day or date.
    var mentionsWhen: Bool
}

/// What RollCall thinks a conversation has planned.
struct PlanSummary: Codable, Equatable {
    var title: String
    var when: String
    var start: Date?
    var hasTime: Bool
    var place: String?
    var who: [String]
    var undecided: String?
    var summary: String
    /// False when the on-device model read the conversation and found no ride plan in it.
    var isPlan: Bool
    /// Written by Apple's on-device model rather than RollCall's own rules.
    var byAI: Bool
}

extension PlanSummary {
    /// How far a plan has got. A **possible plan** meets every criterion: people are arranging a ride or bike event,
    /// on a day still to come, with a time and a place (a meeting point or destination). A **partial plan** is a ride
    /// being arranged that's still missing some of those. Nil when it isn't a ride plan or it's over.
    enum Readiness: Equatable {
        case ready
        case partial(missing: [String])
    }

    func readiness(now: Date = Date()) -> Readiness? {
        guard isPlan else { return nil }
        if let start, start.addingTimeInterval(hasTime ? 3 * 3600 : 86400) < now { return nil }
        var missing: [String] = []
        if start == nil { missing.append("day") }
        if !hasTime { missing.append("time") }
        if (place ?? "").isEmpty { missing.append("place") }
        return missing.isEmpty ? .ready : .partial(missing: missing)
    }

    var isReady: Bool { readiness() == .ready }

    /// What goes in the calendar event: a plain description of the plan, never the chat messages themselves.
    /// Apple Intelligence's summary is already that; RollCall's own guess quotes a message, so it's described instead.
    var calendarNote: String {
        if byAI && !summary.isEmpty { return summary }
        var parts = ["Ride plan: \(title), \(when)."]
        if let place, !place.isEmpty { parts.append("Meeting at \(place).") }
        if !who.isEmpty { parts.append("Going: \(who.joined(separator: ", ")).") }
        if let undecided { parts.append("Still to agree: \(undecided.lowercased()).") }
        return parts.joined(separator: " ")
    }
}

/// A conversation in a chosen chat that mentions times or days, for the user to look over.
struct PlanReview: Codable, Equatable {
    enum Status: String, Codable { case open, added, dismissed }

    var id: String
    var feedID: String
    var chatID: String
    var lines: [ChatLine]
    var summary: PlanSummary
    var status: Status
    var created: Date
    var updated: Date
    var rideID: String?
    /// When you dismissed it with Not a ride. Its messages are kept for a while after (Settings → Privacy),
    /// so it can be brought back; nil when RollCall itself found no plan in it.
    var dismissed: Date? = nil

    /// The message to jump to in Beeper: the latest one that mentioned when.
    var keyMessage: ChatLine? { lines.last(where: \.mentionsWhen) ?? lines.last }
}

/// Finds conversations worth reviewing in a chat's recent messages.
enum PlanFinder {
    /// A quiet gap this long starts a new conversation.
    static let gap: TimeInterval = 3 * 3600
    /// Busy group chats rarely go quiet, so a plan's context is the messages around it:
    /// a little before (what led up to it) and the replies after.
    static let before: TimeInterval = 45 * 60
    static let after: TimeInterval = 2 * 3600
    static let maxLines = 25

    static let dayWords = #"\b(today|tonight|tonite|tomorrow|tmrw|tmr|tomoz|this (morning|arvo|avo|afternoon|evening|weekend|wknd)|next (week|weekend|wknd)|the weekend|later (on|today)|a bit later|(sunday|monday|tuesday|wednesday|thursday|friday|saturday)s?|(this|next|on) (sun|mon|tue|tues|wed|thu|thur|thurs|fri|sat))\b"#

    /// True when the text names a time ("8:30", "9am"), a day ("Sunday", "tomorrow") or a date ("15/11").
    static func mentionsWhen(_ text: String) -> Bool {
        let t = text.lowercased().replacingOccurrences(of: "’", with: "'")
        return RidePlan.clockTime(t) != nil
            || RidePlan.has(#"\b\d{1,2} ?ish\b"#, t)
            || RidePlan.has(dayWords, t)
            || RidePlan.has(TextDetect.absoluteDate, t)
    }

    static func line(from post: PostItem, sender: String?) -> ChatLine {
        ChatLine(id: post.id, sender: sender ?? "", sent: post.published ?? Date(), text: post.text,
                 mentionsWhen: mentionsWhen(post.text))
    }

    /// Splits messages into conversations at quiet gaps.
    static func conversations(_ lines: [ChatLine]) -> [[ChatLine]] {
        var out: [[ChatLine]] = []
        for l in lines.sorted(by: { $0.sent < $1.sent }) {
            if let last = out.last?.last, l.sent.timeIntervalSince(last.sent) <= gap {
                out[out.count - 1].append(l)
            } else {
                out.append([l])
            }
        }
        return out
    }

    static func isTrigger(_ l: ChatLine) -> Bool {
        l.mentionsWhen && !RidePlan.has(RidePlan.saleWords, l.text) && !RidePlan.has(RidePlan.pastWords, l.text)
    }

    /// The messages around each one that names a time or day, joined where they overlap.
    static func clusters(_ lines: [ChatLine]) -> [[ChatLine]] {
        let sorted = lines.sorted { $0.sent < $1.sent }
        var spans: [(from: Date, to: Date)] = []
        for t in sorted where isTrigger(t) {
            let span = (from: t.sent.addingTimeInterval(-before), to: t.sent.addingTimeInterval(after))
            if let last = spans.last, span.from <= last.to {
                spans[spans.count - 1].to = max(last.to, span.to)
            } else {
                spans.append(span)
            }
        }
        return spans.map { s in sorted.filter { $0.sent >= s.from && $0.sent <= s.to } }
    }

    /// Conversations about riding where a new message names a time, day or date.
    /// `newIDs` are messages not seen before, so each conversation is only raised again when it moves on.
    static func find(_ lines: [ChatLine], newIDs: Set<String>, feedID: String, chatID: String, now: Date,
                     calendar: Calendar = .current) -> [PlanReview] {
        var found: [PlanReview] = []
        for cluster in clusters(lines) {
            let triggers = cluster.filter(isTrigger)
            guard let first = triggers.first, triggers.contains(where: { newIDs.contains($0.id) }),
                  cluster.contains(where: { RidePlan.has(RidePlan.rideWords, $0.text) || RideWords.matches($0.text, strict: true) })
            else { continue }
            // Keep what led up to the first mention of a time, then as many replies as fit.
            let firstIndex = cluster.firstIndex(of: first) ?? 0
            let kept = Array(cluster[max(0, firstIndex - 4)...].prefix(maxLines))
            let summary = guess(kept, now: now, calendar: calendar)
            // Skip plans that are already over, and old conversations that never said when.
            if let start = summary.start {
                if start.addingTimeInterval(summary.hasTime ? 3 * 3600 : 86400) < now { continue }
            } else if let last = cluster.last, now.timeIntervalSince(last.sent) > 36 * 3600 {
                continue
            }
            found.append(PlanReview(id: "plan:\(feedID):\(first.id)", feedID: feedID, chatID: chatID, lines: kept,
                                    summary: summary, status: .open, created: now, updated: now))
        }
        return found
    }

    /// How long a conversation under review with no day yet keeps collecting replies as people settle the details.
    static let followFor: TimeInterval = 4 * 86400

    /// A plan (or the ride added from it, going, skipped or not decided yet) takes in replies until the ride is
    /// over, so a change of time or place a few days later still reaches it; one with no day yet, for `followFor`.
    static func following(_ r: PlanReview, now: Date) -> Bool {
        guard let start = r.summary.start else { return now.timeIntervalSince(r.updated) <= followFor }
        return start.addingTimeInterval(r.summary.hasTime ? 3 * 3600 : 86400) > now
    }

    /// Conversations already under review (or added as rides) with new messages that add to them: the time, day or
    /// place, ride talk, people saying they're in, or quick replies. A newly found conversation in the same chat
    /// about the same day joins the one already there instead of being a second plan. Returns the reviews that grew.
    static func followUps(_ lines: [ChatLine], newIDs: Set<String>, found: inout [PlanReview], existing: [PlanReview], now: Date) -> [PlanReview] {
        var grown: [PlanReview] = []
        let sorted = lines.sorted { $0.sent < $1.sent }
        for var r in existing where following(r, now: now) {
            guard let lastSent = r.lines.last?.sent else { continue }
            var adding: [ChatLine] = []
            var previous = lastSent
            for l in sorted where newIDs.contains(l.id) && l.sent > lastSent && !r.lines.contains(where: { $0.id == l.id }) {
                let relevant = l.mentionsWhen || RidePlan.place(in: l.text) != nil || RidePlan.has(RidePlan.rideWords, l.text)
                    || RidePlan.has(yesWords, l.text.lowercased()) || l.sent.timeIntervalSince(previous) <= 20 * 60
                if relevant { adding.append(l); previous = l.sent }
            }
            // The same plan raised again: its messages join this one.
            let sameDay = { (a: Date?, b: Date?) in a == nil || b == nil || Calendar.current.isDate(a!, inSameDayAs: b!) }
            if let i = found.firstIndex(where: { $0.chatID == r.chatID && sameDay($0.summary.start, r.summary.start) }) {
                adding += found[i].lines.filter { l in !r.lines.contains { $0.id == l.id } && !adding.contains { $0.id == l.id } }
                found.remove(at: i)
            }
            guard !adding.isEmpty else { continue }
            let all = (r.lines + adding).sorted { $0.sent < $1.sent }
            // Keep how it started and the latest replies.
            r.lines = all.count > maxLines ? Array(all.prefix(5) + all.suffix(maxLines - 5)) : all
            r.updated = now
            r.summary = guess(r.lines, now: now)
            grown.append(r)
        }
        return grown
    }

    // MARK: Best guess without the on-device model

    static let yesWords = #"\b(i'?m in|im in|keen|count me in|me too|i'?ll (be there|come|join)|see (you|ya|u) (there|then)|sounds good|i can (make|come|do)|i'?m down|down for|yes|yep|yeah|deal|on my way|omw)\b"#

    static func guess(_ lines: [ChatLine], now: Date, calendar: Calendar = .current) -> PlanSummary {
        let triggers = lines.filter(\.mentionsWhen)
        var start: Date?, hasTime = false
        // The latest message that pins down a time usually has the agreed plan. A reply like
        // "meet at 2pm" gives the time; the day comes from earlier in the conversation.
        var laterTime: (Int, Int)?
        for l in triggers.reversed() {
            if let (s, t) = RidePlan.when(in: l.text, sent: l.sent, now: now, calendar: calendar) {
                start = s; hasTime = t
                if let (h, m) = laterTime {
                    start = calendar.date(bySettingHour: h, minute: m, second: 0, of: s) ?? s
                    hasTime = true
                }
                break
            }
            if laterTime == nil { laterTime = RidePlan.clockTime(l.text.lowercased()) }
        }
        if start == nil, let (h, m) = laterTime, let l = triggers.last {
            start = calendar.date(bySettingHour: h, minute: m, second: 0, of: l.sent)
            hasTime = true
        }
        let place = lines.reversed().lazy.compactMap { RidePlan.place(in: $0.text) }.first
        let proposer = (triggers.first ?? lines.first).map(\.sender) ?? ""
        var who: [String] = []
        let firstSent = triggers.first?.sent ?? .distantPast
        for l in lines where !l.sender.isEmpty && l.sent >= firstSent && (l.sender == proposer || RidePlan.has(yesWords, l.text)) {
            if !who.contains(l.sender) { who.append(l.sender) }
        }
        // Without the on-device model, only raise it when a message clearly plans a ride.
        let clear = triggers.contains { RidePlan.judge($0.text, sent: $0.sent, now: $0.sent, calendar: calendar).kind == .ride }
        var open: [String] = []
        if place == nil { open.append("where to meet") }
        if !hasTime { open.append("what time") }
        let first = triggers.first ?? lines[0]
        let quote = first.text.count > 110 ? String(first.text.prefix(107)) + "…" : first.text
        var summary = (first.sender.isEmpty ? "Someone" : first.sender) + " wrote: “\(quote)”"
        let replies = lines.count - 1
        if replies > 0 { summary += " \(replies) message\(replies == 1 ? "" : "s") in the conversation." }
        return PlanSummary(title: TextDetect.title(from: first.text), when: describe(start, hasTime: hasTime),
                           start: start, hasTime: hasTime, place: place, who: who,
                           undecided: open.isEmpty ? nil : open.joined(separator: " and ").capitalizedFirst,
                           summary: summary, isPlan: clear, byAI: false)
    }

    static func describe(_ start: Date?, hasTime: Bool) -> String {
        guard let start else { return "Not settled" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_AU")
        f.dateFormat = hasTime ? "EEEE d MMMM, h:mm a" : "EEEE d MMMM"
        f.amSymbol = "am"; f.pmSymbol = "pm"
        return f.string(from: start)
    }
}

/// Summarises a conversation with Apple's on-device model (nothing leaves the Mac),
/// falling back to RollCall's own best guess when the model isn't available or declines.
enum PlanSummariser {
    static var modelAvailable: Bool { AppleModel.available }

    static func summarise(_ review: PlanReview, chatName: String, now: Date = Date()) async -> PlanSummary {
        let fallback = PlanFinder.guess(review.lines, now: now)
        guard let reply = await AppleModel.ask(instructions: instructions(now: now), input(review.lines, chatName: chatName))
        else { return fallback }
        guard let summary = parse(reply, fallback: fallback, now: now) else { return fallback }
        // The small model sometimes says no to a plain invite; RollCall's own rules win when they're sure,
        // and its summary is used, since the model's describes "no plan".
        if !summary.isPlan, fallback.isPlan { return fallback }
        return summary
    }

    static func instructions(now: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_AU")
        f.dateFormat = "EEEE d MMMM yyyy, h:mm a"
        return """
        You help a motorcyclist keep track of group rides, meetups and other motorbike events \
        that people plan or announce in group chats. Group chats are casual: slang, swearing, jokes and typos \
        are normal, and words left out show as "…". \
        Today is \(f.string(from: now)). Read the chat conversation and work out what, if anything, is being planned. \
        Use the time each message was sent to work out what "today", "tomorrow" or "Sunday" meant. \
        Only describe what the messages actually say. Never invent an activity, place, time or person: \
        if the messages don't name a meeting point or destination, WHERE is unknown, and a vague area such as \
        "in the west" is not a place. Reply in exactly this format, one item per line:
        PLAN: yes or no (yes if people are arranging or announcing a ride, meetup or motorbike event)
        TITLE: a short name for the ride, meetup or event. If the messages say where it starts or where it goes, name it after those places, like "Yarra Glen to Sugarloaf Reservoir" or "Ride to Marysville". Never name it after a person
        WHEN: the agreed or proposed day and time in plain words (say "afternoon" or "evening" if no exact time was given), or unknown
        DATE: the start as YYYY-MM-DD HH:MM in 24-hour time only if someone gave an exact time, otherwise YYYY-MM-DD, or unknown
        WHERE: the meeting point or destination, or unknown
        WHO: names of people who said they're coming (not everyone who posted), separated by commas, or nobody
        UNDECIDED: what still isn't agreed, or nothing
        SUMMARY: one or two plain sentences describing the plan so far
        """
    }

    /// The conversation for the model: each message with when it was sent and who sent it. The messages that
    /// say when are kept if it has to be trimmed.
    static func input(_ lines: [ChatLine], chatName: String) -> AppleModel.Input {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_AU")
        f.dateFormat = "EEE d MMM h:mm a"
        let body = lines.map { l in
            let text = l.text.replacingOccurrences(of: "\n", with: " ")
            return "[\(f.string(from: l.sent))] \(l.sender.isEmpty ? "Someone" : l.sender): \(text.count > 280 ? String(text.prefix(277)) + "…" : text)"
        }
        return AppleModel.Input(heading: "Chat: \(chatName)", lines: body,
                                keep: Set(lines.indices.filter { lines[$0].mentionsWhen }.suffix(4)))
    }

    static func prompt(_ lines: [ChatLine], chatName: String) -> String {
        AppleModel.fitted(input(lines, chatName: chatName), maxChars: AppleModel.maxChars)
    }

    /// Reads the model's reply. Returns nil if it didn't follow the format.
    static func parse(_ reply: String, fallback: PlanSummary, now: Date) -> PlanSummary? {
        var fields: [String: String] = [:]
        for raw in reply.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "**", with: "")
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).uppercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if ["PLAN", "TITLE", "WHEN", "DATE", "WHERE", "WHO", "UNDECIDED", "SUMMARY"].contains(key) { fields[key] = value }
        }
        guard let plan = fields["PLAN"], let summary = fields["SUMMARY"], !summary.isEmpty else { return nil }
        func known(_ key: String) -> String? {
            guard let v = fields[key], !v.isEmpty,
                  !["unknown", "none", "nobody", "nothing", "nothing yet", "no", "n/a", "not specified", "unclear", "no title"].contains(v.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))) else { return nil }
            return v
        }
        var start = fallback.start, hasTime = fallback.hasTime
        // A time written in the messages ("8:30", "around 8ish") is read more reliably by RollCall's own rules.
        if !fallback.hasTime, let d = known("DATE") {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            for (pattern, timed) in [("yyyy-MM-dd HH:mm", true), ("yyyy-MM-dd", false)] {
                f.dateFormat = pattern
                // Only trust dates that make sense: not long past, not far off.
                if let date = f.date(from: d), date > now.addingTimeInterval(-2 * 86400), date < now.addingTimeInterval(180 * 86400) {
                    start = date; hasTime = timed
                    break
                }
            }
        }
        let who = known("WHO").map { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        return PlanSummary(
            title: known("TITLE") ?? fallback.title,
            when: fallback.hasTime ? fallback.when : known("WHEN") ?? PlanFinder.describe(start, hasTime: hasTime),
            start: start, hasTime: hasTime,
            place: known("WHERE").flatMap { vagueArea($0) ? nil : $0 } ?? fallback.place,
            who: who ?? fallback.who,
            undecided: known("UNDECIDED"),
            summary: summary,
            isPlan: plan.lowercased().hasPrefix("y"),
            byAI: true)
    }
}

/// "West", "the north side", "around the east": an area, not a meeting point.
func vagueArea(_ s: String) -> Bool {
    RidePlan.has(#"^(the |around the |in the )?(north|south|east|west|inner|outer|city|cbd|north-?east|north-?west|south-?east|south-?west)( side| suburbs| coast)?$"#,
                 s.trimmingCharacters(in: .whitespaces).lowercased())
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
