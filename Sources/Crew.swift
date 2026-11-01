import Foundation

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
        f.dateFormat = "dMMM"
        return f
    }()

    static let filler: Set<String> = ["the", "a", "an", "and", "of", "to", "with", "for", "at", "on", "in",
                                      "ride", "rides", "riding", "group", "event", "meet", "rollcall"]

    /// The ride's tag, the same on every RollCall for the same ride: "#RC" + the first words of the name + the date,
    /// like #RCHalloweenPreMeet31Oct. A tag already in the event's text (someone's invite) wins, so everyone matches.
    static func rideTag(_ ride: RideEvent, override: String? = nil) -> String {
        if let o = override?.trimmingCharacters(in: .whitespaces), !o.isEmpty { return o.hasPrefix("#") ? o : "#" + o }
        for text in [ride.notes, ride.title] {
            if let r = text.range(of: #"#RC[A-Za-z0-9]{3,}"#, options: .regularExpression) { return String(text[r]) }
        }
        let words = ride.title
            .folding(options: .diacriticInsensitive, locale: nil)
            .replacingOccurrences(of: "-", with: "")  // "Pre-Meet" stays one word
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !filler.contains($0.lowercased()) && Int($0) == nil }
        // Keep capitals inside a word (PreMeet), but tame ones written all in capitals (TTR RETURNS).
        let name = words.prefix(2).map { w in
            let rest = w == w.uppercased() && w.count > 3 ? w.dropFirst().lowercased() : String(w.dropFirst())
            return w.prefix(1).uppercased() + rest
        }.joined()
        return "#RC" + (name.isEmpty ? "Ride" : name) + dateTag.string(from: ride.start)
    }

    /// Splits "hooligoon, #melb riders" into ["#hooligoon", "#melbriders"]-style tags.
    static func tags(in text: String?) -> [String] {
        guard let text else { return [] }
        return text.components(separatedBy: CharacterSet(charactersIn: " ,;\n")).compactMap { w in
            let t = w.trimmingCharacters(in: CharacterSet(charactersIn: "#").union(.whitespaces))
            return t.isEmpty ? nil : "#" + t
        }
    }

    /// The ride's tag, then the group's tags, then yours, without repeats.
    static func hashtags(_ ride: RideEvent, together: Together, links: CrewLinks?, override: String?) -> [String] {
        var seen = Set<String>()
        return ([rideTag(ride, override: override), "#RollCall"] + tags(in: links?.tags) + tags(in: together.tags))
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

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
