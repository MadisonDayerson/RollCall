import Foundation

/// The same ride or plan posted in more than one place: a club's event shared to a forum and Facebook,
/// or one message sent to several group chats. RollCall shows each once.
enum CrossPost {
    private static let filler: Set<String> = ["the", "a", "an", "and", "to", "of", "at", "in", "on", "for", "with", "from",
                                              "ride", "rides", "riding", "run", "bike", "bikes", "motorbike", "motorcycle",
                                              "moto", "event", "meet", "meetup", "group", "our", "this", "my", "your"]

    /// The words that tell rides apart, ignoring case, punctuation, dates and filler.
    static func words(_ s: String) -> Set<String> {
        Set(s.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 && !filler.contains($0) && $0.rangeOfCharacter(from: .letters) != nil })
    }

    /// How much of the shorter text the longer one also says (1 = all of it).
    static func overlap(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        return Double(a.intersection(b).count) / Double(min(a.count, b.count))
    }

    /// Same day and time (within a couple of hours), and either the same name or the same place.
    static func sameRide(_ a: RideEvent, _ b: RideEvent) -> Bool {
        guard a.id != b.id else { return false }
        if a.allDay || b.allDay {
            guard Calendar.current.isDate(a.start, inSameDayAs: b.start) else { return false }
        } else if abs(a.start.timeIntervalSince(b.start)) > 2 * 3600 { return false }
        let ta = words(a.title), tb = words(b.title)
        // A short name like "Sunday ride" says too little to go on.
        if min(ta.count, tb.count) >= 2, overlap(ta, tb) >= 0.75 { return true }
        if !ta.isEmpty, ta == tb, abs(a.start.timeIntervalSince(b.start)) < 60 { return true }
        // Same place and time, and the names agree once the place is taken out of them
        // ("Geelong Bike Night" at Geelong Waterfront and "November bike night" there).
        let pa = words(a.location), pb = words(b.location)
        guard min(pa.count, pb.count) >= 2, overlap(pa, pb) >= 0.75, abs(a.start.timeIntervalSince(b.start)) <= 30 * 60 else { return false }
        return overlap(ta.subtracting(pa).subtracting(pb), tb.subtracting(pa).subtracting(pb)) >= 0.5
    }

    /// The same message (near enough) in different chats.
    static func samePlan(_ a: PlanReview, _ b: PlanReview) -> Bool {
        guard a.id != b.id, a.chatID != b.chatID, let ka = a.keyMessage?.text, let kb = b.keyMessage?.text else { return false }
        let wa = words(ka), wb = words(kb)
        return min(wa.count, wb.count) >= 5 && overlap(wa, wb) >= 0.9
            && Double(min(wa.count, wb.count)) / Double(max(wa.count, wb.count)) >= 0.8
    }

    /// Sorts items into sets that are the same thing, in the order they first appear.
    static func groups<T>(_ items: [T], same: (T, T) -> Bool) -> [[T]] {
        var out: [[T]] = []
        for item in items {
            if let i = out.firstIndex(where: { $0.contains { same($0, item) } }) { out[i].append(item) } else { out.append([item]) }
        }
        return out
    }
}
