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

/// Every request to Apple's on-device model goes through here, prepared so the model will take it:
/// - Its blocking filter is set to the mode Apple provides for reading people's own messages
///   (`permissiveContentTransformations`), since RollCall only ever asks for plain text back.
/// - Swearing and slurs are left out (the model itself can still refuse over them), long tracking links are
///   shortened and junk characters removed.
/// - The text is trimmed to fit the model's short memory (4,096 tokens), keeping the messages that matter.
/// - When it still says no, it tries once more in a way that suits the reason: less text, only the key
///   messages, only messages in a language it reads, or after a short wait when it's busy.
/// - One request at a time, as the model allows.
/// Nothing leaves the Mac, and the messages themselves are never changed: only what the model reads.
enum AppleModel {
    enum Failure: Error, Equatable { case unavailable, filtered, refused, tooLong, language, busy, other }

    /// What to read: a heading, then lines (messages, or a post). `keep` marks lines that stay when it's trimmed.
    struct Input: Equatable {
        var heading: String
        var lines: [String]
        var keep: Set<Int> = []

        /// The original text, for checking a link the model gives back.
        var text: String { ([heading] + lines).joined(separator: "\n") }
    }

    /// Apple Intelligence is on and the model is ready (macOS 26 or later).
    static var available: Bool {
        guard #available(macOS 26, *) else { return false }
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// About a third of the model's memory, which leaves room for the instructions and its reply.
    static let maxChars = 6000

    static func ask(instructions: String, _ input: Input) async -> String? {
        guard available, #available(macOS 26, *) else { return nil }
        await turn.enter()
        defer { Task { await turn.leave() } }
        var input = input
        var budget = maxChars
        var waited = false
        for _ in 0..<4 {
            switch await once(instructions, fitted(input, maxChars: budget)) {
            case .success(let reply):
                guard looksLikeRefusal(reply) else { return reply }
                guard let fewer = keyOnly(input) else { return nil }
                input = fewer
            case .failure(.tooLong):
                budget /= 2
            case .failure(.filtered), .failure(.refused):
                guard let fewer = keyOnly(input) else { return nil }
                input = fewer
            case .failure(.language):
                guard let readable = readableOnly(input) else { return nil }
                input = readable
            case .failure(.busy) where !waited:
                waited = true
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            default:
                return nil
            }
        }
        return nil
    }

    @available(macOS 26, *)
    private static func once(_ instructions: String, _ prompt: String) async -> Result<String, Failure> {
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        let session = LanguageModelSession(model: model, instructions: instructions)
        do {
            // Greedy sampling gives the same answer for the same text every time.
            return .success(try await session.respond(to: prompt, options: GenerationOptions(sampling: .greedy)).content)
        } catch {
            return .failure(failure(error))
        }
    }

    /// macOS 26 and 27 name the model's errors differently.
    @available(macOS 26, *)
    static func failure(_ error: Error) -> Failure {
        if #available(macOS 27, *) {
            if let e = error as? LanguageModelError {
                switch e {
                case .contextSizeExceeded: return .tooLong
                case .rateLimited, .timeout: return .busy
                case .guardrailViolation: return .filtered
                case .refusal: return .refused
                case .unsupportedLanguageOrLocale: return .language
                default: return .other
                }
            }
            if let e = error as? LanguageModelSession.Error, e == .concurrentRequests { return .busy }
        }
        if let e = error as? LanguageModelSession.GenerationError {
            switch e {
            case .exceededContextWindowSize: return .tooLong
            case .rateLimited, .concurrentRequests: return .busy
            case .guardrailViolation: return .filtered
            case .refusal: return .refused
            case .unsupportedLanguageOrLocale: return .language
            case .assetsUnavailable: return .unavailable
            default: return .other
            }
        }
        return .other
    }

    // MARK: Preparing the text

    /// Group chats swear. The model can refuse a whole conversation over one slur or swear word,
    /// so those are left out of what it reads.
    static func tidied(_ text: String) -> String {
        text.replacingOccurrences(of: #"(?i)\b(?:retard\w*|f+u+c+k\w*|fck\w*|sh[i1]t\w*|c+u+n+t\w*|bitch\w*|fag\w*|wank\w*|twat\w*|dickhead\w*|motherf\w*|bastard\w*|slut\w*|whore\w*|n[i1]gg\w*|spastic\w*|tranny\w*)"#,
                                  with: "…", options: .regularExpression)
    }

    /// A link without its tracking (`?fbclid=…`), and no longer than it needs to be to recognise.
    static func shortened(_ link: String) -> String {
        var l = link
        if let q = l.firstIndex(where: { $0 == "?" || $0 == "#" }) { l = String(l[..<q]) }
        return l.count > 100 ? String(l.prefix(100)) : l
    }

    /// What the model reads: swearing hidden, links shortened, invisible characters, runs of the same
    /// character ("!!!!!!!!", "hahahahahaha") and extra spaces cut down.
    static func prepared(_ text: String) -> String {
        var t = tidied(text)
        let links = try! NSRegularExpression(pattern: #"https?://[^\s<>"]+"#)
        for m in links.matches(in: t, range: NSRange(t.startIndex..., in: t)).reversed() {
            if let r = Range(m.range, in: t) { t.replaceSubrange(r, with: shortened(String(t[r]))) }
        }
        t = t.unicodeScalars.filter { !(CharacterSet.controlCharacters.contains($0) && $0 != "\n") && !["\u{200B}", "\u{200C}", "\u{200D}", "\u{FEFF}", "\u{2060}"].contains($0) }
            .map(String.init).joined()
        t = t.replacingOccurrences(of: #"(.)\1{3,}"#, with: "$1$1$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(\S{2,4}?)\1{3,}"#, with: "$1$1$1", options: .regularExpression)
        return t.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
    }

    /// The prepared text in no more than `maxChars`: the oldest lines go first, then long kept lines are cut.
    static func fitted(_ input: Input, maxChars: Int) -> String {
        var lines = input.lines.enumerated().map { (i: $0.offset, text: prepared($0.element)) }
        let heading = prepared(input.heading)
        func size() -> Int { heading.count + 2 + lines.reduce(0) { $0 + $1.text.count + 1 } }
        while size() > maxChars, let drop = lines.firstIndex(where: { !input.keep.contains($0.i) }), lines.count > 1 {
            lines.remove(at: drop)
        }
        while size() > maxChars, let longest = lines.indices.max(by: { lines[$0].text.count < lines[$1].text.count }),
              lines[longest].text.count > 40 {
            let over = size() - maxChars
            lines[longest].text = String(lines[longest].text.prefix(max(40, lines[longest].text.count - over - 1))) + "…"
        }
        return heading + "\n\n" + lines.map(\.text).joined(separator: "\n")
    }

    /// Just the lines that matter (or the last few), for a second try. Nil when that's already all there is.
    static func keyOnly(_ input: Input) -> Input? {
        let keep = input.keep.isEmpty ? Set(input.lines.indices.suffix(3)) : input.keep
        guard keep.count < input.lines.count else { return nil }
        let order = input.lines.indices.filter(keep.contains)
        return Input(heading: input.heading, lines: order.map { input.lines[$0] }, keep: Set(order.indices))
    }

    /// Lines mostly in a script the model reads (Latin letters). Nil when nothing would change.
    static func readableOnly(_ input: Input) -> Input? {
        let order = input.lines.indices.filter { mostlyLatin(input.lines[$0]) }
        guard !order.isEmpty, order.count < input.lines.count else { return nil }
        return Input(heading: input.heading, lines: order.map { input.lines[$0] },
                     keep: Set(order.enumerated().filter { input.keep.contains($0.element) }.map(\.offset)))
    }

    static func mostlyLatin(_ s: String) -> Bool {
        let letters = s.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return true }
        return Double(letters.filter { $0.value < 0x250 }.count) / Double(letters.count) >= 0.6
    }

    /// With the filter relaxed, the model says no in words instead of with an error.
    static func looksLikeRefusal(_ reply: String) -> Bool {
        reply.trimmingCharacters(in: .whitespacesAndNewlines)
            .range(of: #"(?i)^(?:i'?m sorry|sorry,? (?:but )?i|i (?:can(?:no|')t|am unable|won'?t)|as an ai|i apologi[sz]e)"#, options: .regularExpression) != nil
    }

    /// The link as it was written, for a shortened one the model gave back. Nil if the text never had it.
    static func originalLink(_ link: String, in text: String) -> String? {
        let links = (try? NSRegularExpression(pattern: #"https?://[^\s<>"]+"#))?.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text).map { String(text[$0]) } } ?? []
        return links.first { $0 == link || shortened($0) == link || ($0.hasPrefix(link) && link.count >= 15) }
    }

    /// One request at a time: the model turns down a second while it's answering.
    private static let turn = Turn()

    private actor Turn {
        private var busy = false
        private var waiting: [CheckedContinuation<Void, Never>] = []

        func enter() async {
            guard busy else { busy = true; return }
            await withCheckedContinuation { waiting.append($0) }
        }

        func leave() {
            if waiting.isEmpty { busy = false } else { waiting.removeFirst().resume() }
        }
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
        TITLE: a short name for the ride, meetup or event
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
        TITLE: a short, clear name for the ride or event in 2 to 7 words, in normal capitals (not all capitals), without dates
        START: when it starts or when people meet, as YYYY-MM-DD HH:MM in 24-hour time, or YYYY-MM-DD if no time was given, or unknown
        END: when it finishes, as YYYY-MM-DD HH:MM, or unknown
        MEET: the meeting point or starting address, or unknown
        DESTINATION: where the ride goes or ends, or unknown
        STOPS: stops on the way, separated by semicolons, or none
        LINK: a web link for the event or route that appears in the text, or unknown
        DETAILS: one to three plain sentences a rider needs: what it is, what to bring, cost, rules. No names of people.
        """
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

/// "West", "the north side", "around the east": an area, not a meeting point.
func vagueArea(_ s: String) -> Bool {
    RidePlan.has(#"^(the |around the |in the )?(north|south|east|west|inner|outer|city|cbd|north-?east|north-?west|south-?east|south-?west)( side| suburbs| coast)?$"#,
                 s.trimmingCharacters(in: .whitespaces).lowercased())
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
