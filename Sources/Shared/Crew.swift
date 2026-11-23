import Foundation
import NaturalLanguage

/// Riding with friends: the apps a crew uses on a ride, and the tags they post under.
///
/// Life360, Cardo and the social apps don't let other apps join in (no public way to read locations,
/// join an intercom group or post for you), so RollCall carries the details instead: every calendar event
/// says where to meet, which Discord and voice chat group to join, which app to share locations in, and
/// the ride's tag, so the whole crew lands in the same places.
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

    /// The line on calendar events.
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

/// How a crew talks on the ride: a helmet intercom, or a call on the phone. Intercoms pair with the phone
/// over Bluetooth and set up groups in their own phone app, so RollCall can't connect them from the Mac;
/// it carries the group or channel in every calendar event.
enum Intercom: String, Codable, CaseIterable {
    case cardo, sena, interphone, uclear, midland, freedconn, lexin, discord, whatsApp, other, none

    var name: String {
        switch self {
        case .cardo: return "Cardo"
        case .sena: return "Sena"
        case .interphone: return "Interphone"
        case .uclear: return "UClear"
        case .midland: return "Midland"
        case .freedconn: return "FreedConn"
        case .lexin: return "LEXIN"
        case .discord: return "Discord voice"
        case .whatsApp: return "WhatsApp call"
        case .other: return "Other"
        case .none: return "None"
        }
    }

    /// A call on the phone rather than a headset to pair.
    var isCall: Bool { self == .discord || self == .whatsApp }

    /// What the group field asks for.
    var groupPrompt: String {
        switch self {
        case .cardo: return "DMC group name, e.g. SUNDAY CREW"
        case .sena: return "Mesh channel or group, e.g. Open Mesh channel 3"
        case .discord: return "Voice channel, e.g. ride-voice"
        case .whatsApp: return "Group chat for the call"
        default: return "Group or channel"
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

    init() {}

    // Every field is optional in the file, so older saves keep working when fields are added.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        locationApp = (try? c.decodeIfPresent(LocationApp.self, forKey: .locationApp)) ?? .findMy
        intercom = (try? c.decodeIfPresent(Intercom.self, forKey: .intercom)) ?? .cardo
        intercomGroup = (try? c.decodeIfPresent(String.self, forKey: .intercomGroup)) ?? ""
        discord = (try? c.decodeIfPresent(String.self, forKey: .discord)) ?? ""
        tags = (try? c.decodeIfPresent(String.self, forKey: .tags)) ?? ""
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
    static func rideTags(_ ride: RideEvent) -> [String] {
        var seen = Set<String>()
        return ([rideCode(ride)] + Array(extraTags(ride).prefix(5))).filter { seen.insert($0.lowercased()).inserted }
    }

    static func extraTags(_ ride: RideEvent) -> [String] {
        var out: [String] = []
        // Tags already in the name or description.
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
    static func hashtags(_ ride: RideEvent, together: Together, links: CrewLinks?) -> [String] {
        var seen = Set<String>()
        return (rideTags(ride) + ["#RollCall"] + tags(in: links?.tags) + tags(in: together.tags))
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
    static func card(_ ride: RideEvent, together: Together, links: CrewLinks?) -> [String] {
        var lines: [String] = []
        if let m = mapLink(ride.location) { lines.append("🗺️ " + m) }
        if let d = discord(together: together, links: links) { lines.append("💬 Discord: " + d) }
        if together.intercom != .none {
            let group = together.intercomGroup.trimmingCharacters(in: .whitespaces)
            lines.append("🎧 \(together.intercom.name)" + (!group.isEmpty ? ": " + group
                : together.intercom.isCall ? ": join the call before we leave" : ": pair up before we leave"))
        }
        if let r = together.locationApp.reminder { lines.append(r) }
        lines.append("📸 Tag your footage " + hashtags(ride, together: together, links: links).joined(separator: " "))
        return lines
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

