import Foundation
import NaturalLanguage

/// Riding with friends: the apps a crew uses before, during and after a ride, and the tags they post under.
///
/// Life360, Cardo and the social apps don't let other apps join in (no public way to read locations,
/// join an intercom group or post for you), so RollCall carries the details instead: every invite,
/// calendar event and caption says where to meet, which Discord and intercom group to join, which app
/// to share locations in, and the ride's tag, so the whole crew lands in the same places.
enum LocationApp: String, Codable, CaseIterable {
    case findMy, life360, googleMaps, whatsApp, none

    var name: String {
        switch self {
        case .findMy: return "Find My"
        case .life360: return "Life360"
        case .googleMaps: return "Google Maps"
        case .whatsApp: return "WhatsApp live location"
        case .none: return "None"
        }
    }

    /// The line on invites and calendar events.
    var reminder: String? {
        switch self {
        case .findMy: return "📡 Share your location in Find My before we head off"
        case .life360: return "📡 Check you're sharing your location in Life360 before we head off"
        case .googleMaps: return "📡 Share your location in Google Maps before we head off"
        case .whatsApp: return "📡 Share your live location in the group chat before we head off"
        case .none: return nil
        }
    }
}

enum Intercom: String, Codable, CaseIterable {
    case cardo, sena, other, none

    var name: String {
        switch self {
        case .cardo: return "Cardo"
        case .sena: return "Sena"
        case .other: return "Other intercom"
        case .none: return "None"
        }
    }
}

/// How someone rides with their friends; set in setup or Settings.
struct Together: Codable, Equatable {
    var locationApp: LocationApp = .findMy
    var intercom: Intercom = .cardo
    /// Group name or how to join, e.g. "DMC group SUNDAY CREW".
    var intercomGroup = ""
    /// A Discord server or voice channel invite.
    var discord = ""
    /// Tags you always post under, e.g. "#hooligoon #melbourneriders".
    var tags = ""
    /// Your handle, for captions.
    var handle = ""

    init() {}

    // Every field is optional in the file, so older saves keep working when fields are added.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        locationApp = (try? c.decodeIfPresent(LocationApp.self, forKey: .locationApp)) ?? .findMy
        intercom = (try? c.decodeIfPresent(Intercom.self, forKey: .intercom)) ?? .cardo
        intercomGroup = (try? c.decodeIfPresent(String.self, forKey: .intercomGroup)) ?? ""
        discord = (try? c.decodeIfPresent(String.self, forKey: .discord)) ?? ""
        tags = (try? c.decodeIfPresent(String.self, forKey: .tags)) ?? ""
        handle = (try? c.decodeIfPresent(String.self, forKey: .handle)) ?? ""
    }
}

/// A group's own Discord and tags, which take the place of (or add to) yours for its rides.
struct CrewLinks: Codable, Equatable {
    var discord: String? = nil
    var tags: String? = nil
}

enum Crew {
    /// Which crew settings a ride's source uses: everything added by hand shares one.
    static func key(forSource source: String) -> String {
        Store.userAdded.contains(source) && source != "facebook" ? "yours" : source
    }

    static let dateTag: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_AU")
        f.dateFormat = "ddMMyyyy"
        return f
    }()

    /// Words in ride names that say what kind of ride it is rather than which one, so they don't become tags.
    static let generic: Set<String> = Set("""
        the a an and or of to with for at on in from by up down out off via vs x is it this that our your my we you
        us all everyone welcome open free join come go going let lets plan planning planned next today tonight
        tomorrow special edition round part vol final season opener closer start finish kickstands kickstand
        ride rides riding rider riders run runs cruise trip tour day days night nights evening morning afternoon
        arvo weekend week weeks bike bikes biker bikers motorbike motorbikes motorcycle motorcycles moto motor
        club crew group social meet meetup pre premeet meeting event events show party bbq breakfast brunch lunch
        dinner coffee cafe pub drinks beers catch returns return back after before first last annual monthly
        weekly new old big little great good best fun easy chill casual twisties hills loop scenic road roads
        street country city coastal coast beach charity fundraiser memorial overnight camping camp track
        practice training session lesson course learner learners beginner beginners women womens ladies girls
        guys only family costume costumes win prize prizes giveaway takeover multistate shindig
        monday tuesday wednesday thursday friday saturday sunday mon tue tues wed thu thurs fri sat sun
        january february march april may june july august september october november december
        jan feb mar apr jun jul aug sep sept oct nov dec am pm vic nsw qld sa wa tas nt act australia
        """.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init))

    /// Brands and events worth a tag of their own when a ride's name mentions them.
    static let known: [(words: [String], tag: String)] = [
        (["halloween", "spooky"], "#Halloween"), (["christmas", "xmas"], "#Christmas"), (["toy run"], "#ToyRun"),
        (["track day", "trackday"], "#TrackDay"), (["new year", "nye"], "#NewYear"), (["easter"], "#Easter"),
        (["anzac"], "#AnzacDay"), (["insta360", "ace pro", "x4", "x5", "x6"], "#insta360"), (["gopro"], "#GoPro"),
        (["cardo"], "#Cardo"), (["sena"], "#Sena"), (["motogp"], "#MotoGP"), (["wsbk", "worldsbk"], "#WorldSBK"),
        (["phillip island"], "#PhillipIsland"), (["krispy kreme"], "#KrispyKreme"),
    ]

    /// The ride's code, the same on every RollCall for the same ride: "#RC" + the date, like #RC03112026.
    static func rideCode(_ ride: RideEvent) -> String { "#RC" + dateTag.string(from: ride.start) }

    /// The ride's code, then tags for its brand, place or occasion (#Hooligoon #Broadford #Halloween).
    /// Tags you typed for the ride replace them.
    static func rideTags(_ ride: RideEvent, override: String? = nil) -> [String] {
        let typed = tags(in: override)
        if !typed.isEmpty { return typed }
        var seen = Set<String>()
        return ([rideCode(ride)] + Array(extraTags(ride).prefix(5))).filter { seen.insert($0.lowercased()).inserted }
    }

    /// The ride's main tag, used to find everyone's posts.
    static func rideTag(_ ride: RideEvent, override: String? = nil) -> String { rideTags(ride, override: override)[0] }

    static func extraTags(_ ride: RideEvent) -> [String] {
        var out: [String] = []
        // Tags already in the name or someone's invite.
        for text in [ride.title, ride.notes] {
            var rest = text[...]
            while let r = rest.range(of: #"#[A-Za-z][A-Za-z0-9_]+"#, options: .regularExpression) {
                let t = String(rest[r])
                if t.lowercased() != "#rollcall" && t != rideCode(ride) { out.append(t) }
                rest = rest[r.upperBound...]
            }
        }
        var title = " " + ride.title.lowercased().replacingOccurrences(of: "-", with: " ") + " "
        for k in known where k.words.contains(where: { title.range(of: #"(?<![a-z0-9])"# + $0 + #"(?![a-z0-9])"#, options: .regularExpression) != nil }) {
            out.append(k.tag)
            for w in k.words { title = title.replacingOccurrences(of: w, with: " ") }
        }
        let day = Calendar.current.dateComponents([.month, .day], from: ride.start)
        if day.month == 10 && day.day == 31 { out.append("#Halloween") }
        if day.month == 12 && (day.day == 24 || day.day == 25) { out.append("#Christmas") }
        out += names(in: ride.title, skipping: Set(known.flatMap { $0.words.flatMap { $0.split(separator: " ").map(String.init) } }))
        out += placeTags(ride.location)
        return out
    }

    /// Names in a ride's name: capitalised words that aren't everyday words, joined when they sit together
    /// ("Black Spur" -> #BlackSpur, "TORQUE & TERROR" -> #TorqueTerror). People's names are left out.
    static func names(in title: String, skipping: Set<String>) -> [String] {
        let people = personalNames(in: title)
        var out: [String] = [], phrase: [String] = []
        func flush() {
            if !phrase.isEmpty && phrase.count <= 3 { out.append("#" + phrase.joined()) }
            phrase = []
        }
        for chunk in title.replacingOccurrences(of: "&", with: " & ").split(separator: " ") {
            if chunk == "&" { continue }  // "Torque & Terror" stays one name
            let edgeL = chunk.first.map { !$0.isLetter && !$0.isNumber } ?? false
            let edgeR = chunk.last.map { !$0.isLetter && !$0.isNumber } ?? false
            if edgeL { flush() }
            for (i, part) in chunk.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "-" && $0 != "'" }).enumerated() {
                if i > 0 { flush() }
                let w = part.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "'s", with: "").replacingOccurrences(of: "'", with: "")
                let lower = w.lowercased()
                let hasDigit = w.contains(where: \.isNumber), hasLetter = w.contains(where: \.isLetter)
                let capital = w.first?.isUppercase ?? false
                let yearish = !hasLetter || lower.range(of: #"^\d*k\d+$"#, options: .regularExpression) != nil
                guard hasLetter, !yearish, capital || hasDigit, !generic.contains(lower), !skipping.contains(lower),
                      !people.contains(lower) else { flush(); continue }
                let acronym = w == w.uppercased() && w.count <= 4  // TTR, DMC
                let mixed = w.dropFirst().contains(where: \.isUppercase) && w != w.uppercased()
                let word = w == w.uppercased() && w.count > 3 ? String(w.prefix(1)) + w.dropFirst().lowercased() : w.prefix(1).uppercased() + w.dropFirst()
                if mixed || hasDigit || acronym { flush(); phrase = [word]; flush() } else { phrase.append(word) }
            }
            if edgeR { flush() }
        }
        flush()
        return out
    }

    static func personalNames(in text: String) -> Set<String> {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var names = Set<String>()
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: [.omitPunctuation, .omitWhitespace]) { tag, r in
            if tag == .personalName { names.insert(text[r].lowercased()) }
            return true
        }
        return names
    }

    /// The venue and town from an address: "Krispy Kreme, 352 Princes Hwy, Narre Warren VIC 3805" ->
    /// #KrispyKreme #NarreWarren. Street addresses, states, postcodes and countries are skipped.
    static func placeTags(_ location: String) -> [String] {
        var text = location
        while let r = text.range(of: #"\([^()]*\)"#, options: .regularExpression) { text.removeSubrange(r) }
        let streets: Set<String> = ["street", "st", "road", "rd", "highway", "hwy", "avenue", "ave", "drive", "dr", "lane",
                                    "parade", "pde", "place", "pl", "way", "boulevard", "bvd", "court", "ct", "crescent",
                                    "cres", "terrace", "tce", "entrance", "near", "corner", "cnr"]
        let parts: [[String]] = text.split(separator: ",").map { part in
            part.split(separator: " ").map(String.init).filter { w in
                let l = w.lowercased()
                return !(l.count == 4 && Int(l) != nil) && !["vic", "victoria", "nsw", "qld", "sa", "wa", "tas", "nt", "act", "australia"].contains(l)
            }
        }.filter { words in
            !words.isEmpty && words.count <= 3 && !(words.first.map { Int($0) != nil } ?? false)
                && !words.contains { streets.contains($0.lowercased()) }
        }
        func tag(_ words: [String]) -> String {
            "#" + words.map { w in
                let clean = w.filter { $0.isLetter || $0.isNumber }
                return clean == clean.uppercased() && clean.count > 3 ? String(clean.prefix(1)) + clean.dropFirst().lowercased() : clean.prefix(1).uppercased() + clean.dropFirst()
            }.joined()
        }
        guard let last = parts.last else { return [] }
        return (parts.count > 1 ? [tag(parts[0])] : []) + [tag(last)]
    }

    /// Splits "hooligoon, #melb riders" into ["#hooligoon", "#melbriders"]-style tags.
    static func tags(in text: String?) -> [String] {
        guard let text else { return [] }
        return text.components(separatedBy: CharacterSet(charactersIn: " ,;\n")).compactMap { w in
            let t = w.trimmingCharacters(in: CharacterSet(charactersIn: "#").union(.whitespaces))
            return t.isEmpty ? nil : "#" + t
        }
    }

    /// The ride's tags, then the group's tags, then yours, without repeats.
    static func hashtags(_ ride: RideEvent, together: Together, links: CrewLinks?, override: String?) -> [String] {
        var seen = Set<String>()
        return (rideTags(ride, override: override) + ["#RollCall"] + tags(in: links?.tags) + tags(in: together.tags))
            .filter { seen.insert($0.lowercased()).inserted }
    }

    static func discord(together: Together, links: CrewLinks?) -> String? {
        let d = (links?.discord ?? "").isEmpty ? together.discord : links!.discord!
        return d.trimmingCharacters(in: .whitespaces).isEmpty ? nil : d.trimmingCharacters(in: .whitespaces)
    }

    static func mapLink(_ place: String) -> String? {
        guard !place.isEmpty, let q = place.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return "https://maps.apple.com/?q=" + q
    }

    /// The crew details: where to meet, how to keep in touch on the day, and what to tag.
    static func card(_ ride: RideEvent, together: Together, links: CrewLinks?, override: String?) -> [String] {
        var lines: [String] = []
        if let m = mapLink(ride.location) { lines.append("🗺️ " + m) }
        if let d = discord(together: together, links: links) { lines.append("💬 Discord: " + d) }
        if together.intercom != .none {
            let group = together.intercomGroup.trimmingCharacters(in: .whitespaces)
            lines.append("🎧 \(together.intercom.name)" + (group.isEmpty ? ": pair up before we leave" : ": " + group))
        }
        if let r = together.locationApp.reminder { lines.append(r) }
        lines.append("📸 Tag your footage " + hashtags(ride, together: together, links: links, override: override).joined(separator: " "))
        return lines
    }

    /// A message to paste into a group chat or Discord, or send with the share menu.
    static func invite(_ ride: RideEvent, when: String, together: Together, links: CrewLinks?, override: String?) -> String {
        var lines = ["🏍️ " + ride.title, "📅 " + when]
        if !ride.location.isEmpty { lines.append("📍 " + ride.location) }
        if let u = ride.url { lines.append("🔗 " + u) }
        lines += card(ride, together: together, links: links, override: override)
        return lines.joined(separator: "\n")
    }

    /// A caption for after the ride, ready to paste under a photo or video.
    static func caption(_ ride: RideEvent, together: Together, links: CrewLinks?, override: String?) -> String {
        var first = ride.title + " 🏍️"
        if !together.handle.isEmpty { first += " with " + (together.handle.hasPrefix("@") ? together.handle : "@" + together.handle) }
        return first + "\n\n" + hashtags(ride, together: together, links: links, override: override).joined(separator: " ")
    }

    /// A calendar file of the ride, attached to invites so friends can add it in one tap.
    static func ics(_ ride: RideEvent, description: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyyMMdd"
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ";", with: "\\;")
                .replacingOccurrences(of: ",", with: "\\,").replacingOccurrences(of: "\n", with: "\\n")
        }
        var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//RollCall//EN", "BEGIN:VEVENT",
                     "UID:\(ride.id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "ride")@rollcall",
                     "DTSTAMP:" + f.string(from: Date())]
        if ride.allDay {
            lines.append("DTSTART;VALUE=DATE:" + day.string(from: ride.start))
            lines.append("DTEND;VALUE=DATE:" + day.string(from: ride.end ?? ride.start.addingTimeInterval(86400)))
        } else {
            lines.append("DTSTART:" + f.string(from: ride.start))
            lines.append("DTEND:" + f.string(from: ride.end ?? ride.start.addingTimeInterval(4 * 3600)))
        }
        lines.append("SUMMARY:" + esc(ride.title))
        if !ride.location.isEmpty { lines.append("LOCATION:" + esc(ride.location)) }
        if let u = ride.url { lines.append("URL:" + u) }
        lines += ["DESCRIPTION:" + esc(description), "END:VEVENT", "END:VCALENDAR"]
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Web pages showing what people posted under a tag.
    static func tagPages(_ tag: String) -> [(name: String, url: String)] {
        let t = tag.trimmingCharacters(in: CharacterSet(charactersIn: "#")).lowercased()
        return [("Instagram", "https://www.instagram.com/explore/tags/\(t)/"),
                ("TikTok", "https://www.tiktok.com/tag/\(t)"),
                ("YouTube", "https://www.youtube.com/hashtag/\(t)")]
    }
}

/// Directions for a ride. A route the organiser shared in the description wins. Otherwise it's from home
/// (the rough spot of your suburb) to the meeting place, any stops, and the destination, read from labelled
/// lines like "Meet point: …", "Stop: …" or "Destination: …".
enum Route {
    struct Stops: Equatable {
        var meet: String?
        var via: [String] = []
        var destination: String?
    }

    /// A directions link in the text: Google Maps or Apple Maps. Short Google links can be a single place,
    /// so they only count on a line that mentions a route or directions.
    static func link(in text: String) -> String? {
        let full = #"https?://(?:www\.|maps\.)?google\.[a-z.]+/maps/dir/[^\s<>"]+|https?://maps\.apple\.com/[^\s<>"]*[?&](?:daddr|destination)=[^\s<>"]+"#
        let short = #"https?://(?:maps\.app\.goo\.gl|goo\.gl/maps)/[^\s<>"]+"#
        for line in text.components(separatedBy: .newlines) {
            if let l = first(full, in: line) { return l }
            if line.range(of: #"(?i)\b(route|directions|ride map|map of the ride)\b"#, options: .regularExpression) != nil,
               let l = first(short, in: line) { return l }
        }
        return nil
    }

    private static func first(_ pattern: String, in line: String) -> String? {
        guard let r = line.range(of: pattern, options: .regularExpression) else { return nil }
        return String(line[r]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]'"))
    }

    static func stops(in text: String) -> Stops {
        var s = Stops()
        let labels: [(kind: Int, pattern: String)] = [
            (0, #"meet(?:ing)?(?: up)?(?: point| spot| place| location)?|start(?:ing)?(?: point)?|kick ?stands? up(?: from)?|depart(?:ing|ure)?(?: from| point)?|leaving from"#),
            (1, #"stops?|via|regroup|fuel(?: stop)?|coffee(?: stop)?|lunch(?: stop)?|break|pit stop|waypoints?"#),
            (2, #"destination|finish(?:ing)?(?: point)?|end(?:ing)?(?: point)?|final stop|ride to|heading to"#),
        ]
        for raw in text.components(separatedBy: .newlines) {
            // Skip bullets and emoji before the label.
            let line = String(raw.drop { !$0.isLetter })
            for (kind, label) in labels {
                let p = #"(?i)^(?:"# + label + #")\s*\d*\s*[:\-–—]\s*(.+)$"#
                guard let re = try? NSRegularExpression(pattern: p),
                      let m = re.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                      let r = Range(m.range(at: 1), in: line) else { continue }
                let places = clean(String(line[r]), split: kind == 1)
                switch kind {
                case 0: if s.meet == nil { s.meet = places.first }
                case 1: s.via += places
                default: if s.destination == nil { s.destination = places.last }
                }
                break
            }
        }
        return s
    }

    /// "6:30pm at Shell Laverton" → "Shell Laverton"; stops can be listed as "A → B; C".
    private static func clean(_ value: String, split: Bool) -> [String] {
        var v = value.replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
        v = v.replacingOccurrences(of: #"(?i)^\s*\d{1,2}(?:[:.]\d{2})?\s*(?:am|pm)?\s*(?:at|@|from|-|–)?\s*"#, with: "",
                                   options: .regularExpression)
        let parts = split ? v.components(separatedBy: CharacterSet(charactersIn: "→;|")).flatMap { $0.components(separatedBy: "->") } : [v]
        return parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,"))) }
            .filter { $0.count >= 3 && $0.rangeOfCharacter(from: .letters) != nil }
    }

    /// The places in order, without repeats next to each other.
    static func places(meetingPlace: String, notes: String) -> [String] {
        let s = stops(in: notes)
        var out: [String] = []
        for p in [s.meet ?? meetingPlace] + s.via + [s.destination ?? ""] where !p.isEmpty {
            if out.last?.lowercased() != p.lowercased() { out.append(p) }
        }
        return out
    }

    /// Google Maps directions in the browser, with every stop. Without a start it begins wherever you are.
    static func googleMaps(from origin: String?, through places: [String]) -> String? {
        guard let destination = places.last else { return nil }
        var c = URLComponents(string: "https://www.google.com/maps/dir/")!
        var q = [URLQueryItem(name: "api", value: "1")]
        if let origin { q.append(URLQueryItem(name: "origin", value: origin)) }
        q.append(URLQueryItem(name: "destination", value: destination))
        if places.count > 1 { q.append(URLQueryItem(name: "waypoints", value: places.dropLast().joined(separator: "|"))) }
        q.append(URLQueryItem(name: "travelmode", value: "driving"))
        c.queryItems = q
        c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "|", with: "%7C")
        return c.string
    }

    /// Apple Maps directions, for a route with no stops in between (its links can't carry them).
    static func appleMaps(from origin: String?, to place: String) -> String {
        var c = URLComponents(string: "maps://")!
        c.queryItems = (origin.map { [URLQueryItem(name: "saddr", value: $0)] } ?? [])
            + [URLQueryItem(name: "daddr", value: place), URLQueryItem(name: "dirflg", value: "d")]
        return c.string ?? "maps://"
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
