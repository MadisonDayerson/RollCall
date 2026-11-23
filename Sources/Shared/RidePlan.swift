import Foundation

/// Decides whether a chat message is planning a ride, as opposed to general bike chat,
/// a report of a ride that already happened, or a for-sale post.
///
/// A message counts when it talks about riding, says when (a date, a day or "this arvo"), and either
/// says where (a meeting point, address or destination) or invites people ("anyone keen?").
/// Days like "Sunday" or "tomorrow" are read relative to when the message was sent.
enum RidePlan {
    struct Verdict {
        enum Kind { case ride, maybe, no }
        var kind: Kind = .no
        var start: Date?
        var hasTime = false
        var place: String?
        var why = ""
    }

    // Talking about riding, bikes or a bike event.
    // "Meet" counts unless it's meeting someone ("going to meet him tonight").
    static let rideWords = #"\b(ride|rides|riding|rideout|ride out|run|cruise|blat|spin|twisties|loop|group ride|bike|bikes|motorbike|motorbikes|motorcycle|motorcycles|bike night|bike show|track day|meet ?up|meet(?! (him|her|them|my|his|their)\b)|head(ing)? (out|off|up|down)|go(ing)? (out )?for a (ride|spin|blat|cruise|lap|run)|brekkie|breakfast|coffee)\b"#

    // Inviting people or announcing a plan.
    static let intentWords = #"\b(anyone|any ?1|anybody) (out|keen|want|wanna|up for|interested|coming|joining|free|riding|going|heading|around|else)|\bwho('?s| is)? (keen|in|coming|up for|joining|free|around|going)\b|\bkeen (for|to|on)\b|\b(thinking|planning|plan) (about |of |on |to )?(going|heading|riding|doing|a ride|a run|a blat|a cruise|head|go|ride)|\blet'?s (go|ride|do|head|meet|get)\b|\bwe('re| are| will|'ll) (be )?(heading|going|riding|meeting|leaving|doing|head|go|ride|meet|leave)\b|\bi('m| am|'ll| will) (be )?(heading|going|riding|leaving|head|go|ride|leave) (out|for|to|up|down|off)\b|\bjoin (us|me|in)\b|\bcome (along|join)\b|\b(all|everyone|anyone) (is )?welcome\b|\bmeet(ing)? (at|@|up at|point|spot|place|location)\b|\bkick ?stands? up\b|\bksu\b|\bleaving (at|from)\b|\bdepart(ing|ure|s)?\b|\broll(ing)? out\b|\brsvp\b|\broute\b|\bride('?s| is) on\b|\bcould meet\b|\bwanna (ride|go|head)\b|\bwant to (ride|go|head|join)\b|\bupcoming\b"#

    // Already happened.
    static let pastWords = #"\b(yesterday|last (night|week|weekend|sun|sunday|sat|saturday|month))\b|\b(was|were) (awesome|great|amazing|epic|fun|good|mint|sick|unreal|insane|wild)\b|\b(rode|went for|had a (great|good|awesome|blast|ball|fun))\b|\bthanks? (you )?(for|everyone|all|guys|girls|heaps)\b|\bthank you\b|\b(great|awesome|good|fun|epic|top) (ride|run|day|night)\b|\b(today|tonight|it) was\b|\b(pics|photos|videos?) from\b|\bhope\b[^.!?]*\b(have|had|has) a (great|good|fun|safe|awesome|lovely)\b|\b(have|had) a (great|good|fun|awesome|safe) (time|ride|one)\b"#

    // Buying, selling, gear and other business.
    static let saleWords = #"\b(for sale|selling|sell|sold|fs|wts|wtb|ono|price|insurance|quote|rego|wanted)\b|\$\s?\d"#

    static func has(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func judge(_ raw: String, sent: Date, now: Date = Date(), calendar: Calendar = .current) -> Verdict {
        var v = Verdict()
        let text = raw.replacingOccurrences(of: "’", with: "'")
        guard has(rideWords, text) else { v.why = "no ride words"; return v }
        if has(saleWords, text) { v.why = "buying or selling"; return v }
        if has(pastWords, text) { v.why = "about a ride that already happened"; return v }

        let intent = has(intentWords, text)
        v.place = place(in: text)
        if let (start, hasTime) = when(in: text, sent: sent, now: now, calendar: calendar) {
            v.start = start
            v.hasTime = hasTime
        }
        let ends = v.start.map { $0.addingTimeInterval(v.hasTime ? 3 * 3600 : 86400) }
        switch (v.start, intent, v.place != nil) {
        case (.some, true, _), (.some, _, true):
            if let ends, ends < now { v.why = "planned, but already over"; return v }
            v.kind = .ride
            v.why = intent ? "invites people and says when" : "says when and where"
        case (nil, true, true):
            v.kind = .maybe
            v.why = "invites people and says where, but not when"
        case (nil, true, false):
            // "Anyone keen for a ride?" with no day: worth a look under "Posts to look at".
            v.kind = .maybe
            v.why = "invites people but doesn't say when"
        default:
            v.why = "ride talk, but no plan"
        }
        return v
    }

    // MARK: When

    static let weekdays = ["sun": 1, "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7]

    /// The ride's start, from a full date in the text, or a day word read relative to when it was sent.
    static func when(in text: String, sent: Date, now: Date, calendar cal: Calendar) -> (Date, Bool)? {
        let t = text.lowercased()
        let time = clockTime(t)

        // A written-out date ("Sun 8 Nov", "15/11") wins.
        let found = TextDetect.scan(text, now: now, absoluteOnly: true)
        if let s = found.start {
            if !found.hasTime, let (h, m) = time {
                return (cal.date(bySettingHour: h, minute: m, second: 0, of: s) ?? s, true)
            }
            return (s, found.hasTime)
        }

        let sentDay = cal.startOfDay(for: sent)
        var day: Date?
        var partHour: Int?
        if has(#"\b(tomorrow|tmrw|tmr|tomoz)\b"#, t) {
            day = cal.date(byAdding: .day, value: 1, to: sentDay)
        } else if has(#"\b(this|next|the) (weekend|wknd)\b"#, t) {
            day = next(weekday: 7, onOrAfter: sentDay, cal)
        } else if let m = t.range(of: #"\b(sunday|monday|tuesday|wednesday|thursday|friday|saturday)s?\b|\b(this|next|on) (sun|mon|tue|tues|wed|thu|thur|thurs|fri|sat)\b"#, options: .regularExpression) {
            // Short names only after "this/next/on", so "sat in the garage" and "the sun's out" don't count.
            // "Next Sunday" is read as the coming Sunday, as most people mean it.
            let word = String(t[m]).replacingOccurrences(of: #"^(this|next|on)\s+"#, with: "", options: .regularExpression)
            if let wd = weekdays[String(word.prefix(3))] { day = next(weekday: wd, onOrAfter: sentDay, cal) }
        } else if has(#"\b(today|tonight|tonite|this (morning|arvo|afternoon|evening|avo)|later (on|today)|this avo)\b"#, t) {
            day = sentDay
        }
        // "Anyone riding at 8?" in a chat means today.
        if day == nil, time != nil { day = sentDay }
        guard let day else { return nil }

        if has(#"\bmorning\b"#, t) { partHour = 9 }
        if has(#"\b(arvo|avo|afternoon)\b"#, t) { partHour = 14 }
        if has(#"\b(evening|tonight|tonite)\b"#, t) { partHour = partHour ?? 18 }
        if let (h, m) = time {
            var start = cal.date(bySettingHour: h, minute: m, second: 0, of: day) ?? day
            // "Meet at 7" sent at 3pm means 7pm, unless they said am.
            if start < sent, h < 12, !has(#"\d\s*(am|a\.m\.)"#, t) { start = start.addingTimeInterval(12 * 3600) }
            return (start, true)
        }
        if let h = partHour { return (cal.date(bySettingHour: h, minute: 0, second: 0, of: day) ?? day, true) }
        // "Heading out a bit later": a couple of hours after the message.
        if has(#"\blater (on|today)\b|\ba bit later\b"#, t), cal.isDate(day, inSameDayAs: sent) {
            let hour = cal.component(.hour, from: sent) + 2
            if hour < 24 { return (cal.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day, true) }
        }
        return (day, false)
    }

    static func next(weekday: Int, onOrAfter day: Date, _ cal: Calendar) -> Date {
        let wd = cal.component(.weekday, from: day)
        return cal.date(byAdding: .day, value: (weekday - wd + 7) % 7, to: day) ?? day
    }

    /// "8:30am", "9am", "7.30pm", "10:00", "leaving at 8" → (hour, minute).
    static func clockTime(_ t: String) -> (Int, Int)? {
        let re = try! NSRegularExpression(pattern: #"\b(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm)\b|\b(\d{1,2})[:.](\d{2})\b"#)
        guard let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) else {
            // A bare "at 8": rides run in daylight, so 1 to 6 means afternoon.
            guard let h = Web.firstMatch(#"\b(?:at|@|from|around|about) (\d{1,2})(?:ish)?\b(?![\d/.:])|\b(\d{1,2}) ?ish\b"#, in: t).flatMap({ Int($0) }),
                  (1...12).contains(h) else { return nil }
            return (h <= 6 ? h + 12 : h, 0)
        }
        func g(_ i: Int) -> String? { Range(m.range(at: i), in: t).map { String(t[$0]) } }
        var h = Int(g(1) ?? g(4) ?? "") ?? 0
        let min = Int(g(2) ?? g(5) ?? "") ?? 0
        if let ap = g(3) {
            if ap == "pm", h < 12 { h += 12 }
            if ap == "am", h == 12 { h = 0 }
        }
        guard (0..<24).contains(h), (0..<60).contains(min) else { return nil }
        return (h, min)
    }

    // MARK: Where

    /// A meeting point or destination: an address, "meet at X", or "ride to X".
    static func place(in text: String) -> String? {
        if let a = TextDetect.scan(text).address { return a }
        let patterns = [
            #"(?i)\b(?:meet(?:ing)?(?: up)?|leaving|departing|starting|start|kick ?stands? up)\s*(?:at|@|from|point:?|spot:?)\s+([^.,!?\n]{3,60})"#,
            // Destinations are names, so the capture must start with a capital letter.
            #"\b(?i:ride|run|blat|cruise|heading|head|going|loop)\s+(?i:up |down |out |over )?(?i:to|through|via)\s+([A-Z][\w'&]+(?:\s+[A-Z][\w'&]+){0,3})"#,
        ]
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p),
                  let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let r = Range(m.range(at: 1), in: text) else { continue }
            let s = text[r].trimmingCharacters(in: .whitespaces)
            if s.count >= 3, !has(#"^(the )?(usual|somewhere|anywhere|some ?where|wherever)\b"#, s) { return s }
        }
        return nil
    }
}
