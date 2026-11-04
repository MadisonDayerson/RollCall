import Foundation

/// The few lines of an event description that matter (where to meet, when to leave, where you're going),
/// in plain words. Long descriptions bury them under links, socials and fine print.
enum Brief {
    struct Item: Equatable {
        var label: String
        var value: String
    }

    /// Labels that only point elsewhere: links, socials and contact details.
    private static let skip = #"(?i)^(?:our )?(?:socials?|facebook|fb|instagram|insta|ig|whatsapp|discord|tiktok|youtube|telegram|website|web|link|links|url|email|e-mail|phone|mobile|contact|google maps(?: route)?|maps?|route|ride map|tickets?|hashtags?|tags?)\b"#

    static func items(in notes: String) -> [Item] {
        var out: [Item] = []
        for raw in Web.readableNotes(notes).components(separatedBy: .newlines) {
            // Skip bullets and emoji before the label.
            let line = String(raw.drop { !$0.isLetter }).trimmingCharacters(in: .whitespaces)
            guard let colon = line.firstIndex(of: ":") else { continue }
            let label = line[..<colon].trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: colon)...])
            // "https://…" splits at its own colon: that's a link, not a label.
            if value.hasPrefix("//") { continue }
            let words = label.split(separator: " ")
            guard !words.isEmpty, words.count <= 4, label.count <= 30, label.rangeOfCharacter(from: CharacterSet.decimalDigits.union(CharacterSet(charactersIn: ".!?,;"))) == nil,
                  label.range(of: skip, options: .regularExpression) == nil else { continue }
            value = value.replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "-–—")))
            guard value.rangeOfCharacter(from: .alphanumerics) != nil else { continue }
            out.append(Item(label: plainLabel(label), value: plainValue(value)))
            if out.count == 6 { break }
        }
        // One labelled line on its own is more likely a sentence with a colon in it.
        return out.count >= 2 ? out : []
    }

    /// Short descriptions read fine as they are; long ones without labelled lines get their first few lines.
    static func needsSummary(_ notes: String) -> Bool {
        let text = Web.readableNotes(notes)
        return text.count > 280 || text.components(separatedBy: .newlines).filter { !$0.isEmpty }.count > 6
            || text.range(of: #"https?://\S{80,}"#, options: .regularExpression) != nil
    }

    /// The opening of a description, links taken out, for when there are no labelled lines to pick from.
    static func opening(_ notes: String, limit: Int = 240) -> String {
        let text = Web.readableNotes(notes)
            .replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
            .components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            .joined(separator: " ")
        let plain = plainValue(text)
        guard plain.count > limit else { return plain }
        let cut = plain.prefix(limit)
        return (cut.range(of: " ", options: .backwards).map { String(cut[..<$0.lowerBound]) } ?? String(cut)) + "…"
    }

    private static func plainLabel(_ label: String) -> String {
        let l = label.lowercased()
        if l.range(of: #"^(?:kick ?stands? up|stands up|ksu|depart(?:ing|ure)?|leaving|wheels up|roll out|rolling out)"#, options: .regularExpression) != nil { return "Leave" }
        if l.range(of: #"^meet"#, options: .regularExpression) != nil { return "Meet" }
        if l.range(of: #"^(?:destination|finish|end point|ending)"#, options: .regularExpression) != nil { return "Finish" }
        return l.prefix(1).uppercased() + l.dropFirst()
    }

    /// Calms down text written in capitals ("NO OPTIONAL RIDE THIS TIME" → "No optional ride this time"),
    /// keeping state names like VIC, and writes times as "7pm".
    static func plainValue(_ value: String) -> String {
        var v = value.replacingOccurrences(of: #"^\s*(?:@|at)\s+(?=\d)"#, with: "", options: [.regularExpression, .caseInsensitive])
        let letters = v.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        let capitals = letters.filter { CharacterSet.uppercaseLetters.contains($0) }
        if letters.count >= 6, Double(capitals.count) / Double(letters.count) > 0.7 {
            let keep: Set<String> = ["VIC", "NSW", "QLD", "SA", "WA", "TAS", "NT", "ACT", "NZ", "UK", "USA", "CBD", "BP"]
            var start = true
            v = v.split(separator: " ", omittingEmptySubsequences: false).map { word -> String in
                let w = String(word)
                let bare = w.trimmingCharacters(in: .punctuationCharacters)
                defer { if !w.isEmpty { start = w.last.map { ".!?".contains($0) } ?? false } }
                if keep.contains(bare) || w.rangeOfCharacter(from: .decimalDigits) != nil { return w }
                let lower = w.lowercased()
                return start ? lower.prefix(1).uppercased() + lower.dropFirst() : lower
            }.joined(separator: " ")
        }
        // "7 PM" → "7pm"
        let times = try! NSRegularExpression(pattern: #"(?i)\b\d{1,2}(?:[:.]\d{2})?\s*[ap]m\b"#)
        for m in times.matches(in: v, range: NSRange(v.startIndex..., in: v)).reversed() {
            if let r = Range(m.range, in: v) { v.replaceSubrange(r, with: v[r].lowercased().replacingOccurrences(of: " ", with: "")) }
        }
        return v
    }
}
