import Foundation

/// Reads events and posts from ordinary web pages.
enum Web {
    static let userAgent = "RollCall/1.0 (personal calendar reader)"

    static func get(_ urlString: String) async throws -> (text: String, contentType: String, finalURL: URL) {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await Net.session.data(for: req)
        let http = response as? HTTPURLResponse
        if let code = http?.statusCode, !(200..<300).contains(code) {
            throw code == 401 || code == 403 ? FeedError.privateFeed : FeedError.http(code)
        }
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        return (text, http?.value(forHTTPHeaderField: "Content-Type") ?? "", http?.url ?? url)
    }

    static func absolute(_ href: String, base: URL) -> String {
        URL(string: decodeEntities(href), relativeTo: base)?.absoluteString ?? href
    }

    // MARK: - Working out what a link is

    /// Looks at a page and decides how to read it.
    static func discover(_ raw: String) async throws -> Feed {
        if let f = FeedLinks.normalise(raw), f.url.contains("meetup.com") || f.url.lowercased().contains(".ics") {
            return f
        }
        guard var feed = FeedLinks.normalise(raw) else { throw FeedError.notCalendar }
        let page = try await get(feed.url)
        let host = page.finalURL.host?.replacingOccurrences(of: "www.", with: "") ?? feed.name
        let title = pageTitle(page.text) ?? host
        feed.name = title
        feed.groupURL = page.finalURL.absoluteString

        if page.text.contains("BEGIN:VCALENDAR") { feed.kind = .calendar; feed.groupURL = nil; return feed }
        if isFeedXML(page.text) { feed.kind = .posts; feed.keywordFilter = true; return feed }
        if isXenForo(page.text) { feed.kind = .forum; feed.keywordFilter = true; return feed }
        if !jsonLDEvents(page.text, base: page.finalURL).isEmpty { feed.kind = .webpage; feed.keywordFilter = true; return feed }
        // A calendar feed linked from the page beats reading the page itself.
        if let ics = calendarLink(page.text, base: page.finalURL) {
            feed.kind = .calendar; feed.url = ics; return feed
        }
        if let rss = feedLink(page.text, base: page.finalURL) {
            feed.kind = .posts; feed.url = rss; feed.keywordFilter = true; return feed
        }
        throw DiscoverError.nothingFound
    }

    static func pageTitle(_ html: String) -> String? {
        for p in [#"<meta property="og:site_name" content="([^"]+)""#, #"<title[^>]*>([^<]+)</title>"#] {
            if let t = firstMatch(p, in: html) {
                let s = decodeEntities(t).trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty { return s.count > 60 ? String(s.prefix(57)) + "…" : s }
            }
        }
        return nil
    }

    static func isFeedXML(_ s: String) -> Bool {
        let head = s.prefix(500).lowercased()
        return head.contains("<rss") || head.contains("<feed") || (head.contains("<?xml") && s.contains("<item"))
    }

    static func isXenForo(_ html: String) -> Bool {
        html.contains("structItem--thread") || (html.contains("XenForo") && html.range(of: #"/events/[a-z0-9-]+\.\d+/"#, options: .regularExpression) != nil)
    }

    static func calendarLink(_ html: String, base: URL) -> String? {
        let patterns = [
            #"<link[^>]+type="text/calendar"[^>]+href="([^"]+)""#,
            #"href="(webcal://[^"]+)""#,
            #"href="([^"]+\.ics(?:\?[^"]*)?)""#,
            #"href="([^"]+[?&]ical=1[^"]*)""#,
        ]
        for p in patterns {
            if let h = firstMatch(p, in: html) {
                let link = h.hasPrefix("webcal://") ? "https://" + h.dropFirst(9) : absolute(h, base: base)
                return link
            }
        }
        return nil
    }

    static func feedLink(_ html: String, base: URL) -> String? {
        firstMatch(#"<link[^>]+type="application/(?:rss|atom)\+xml"[^>]+href="([^"]+)""#, in: html)
            .map { absolute($0, base: base) }
    }

    // MARK: - schema.org events embedded in pages (Eventbrite, Humanitix, club sites, Squarespace, Wix…)

    static func jsonLDEvents(_ html: String, base: URL) -> [ICSEvent] {
        var out: [ICSEvent] = []
        let blocks = allMatches(#"<script[^>]*type=["']application/ld\+json["'][^>]*>(.*?)</script>"#, in: html)
        for b in blocks {
            guard let data = b.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            walk(json) { dict in
                if let e = event(from: dict, base: base) { out.append(e) }
            }
        }
        var seen = Set<String>()
        return out.filter { seen.insert($0.uid).inserted }
    }

    static func walk(_ any: Any, _ visit: ([String: Any]) -> Void) {
        if let arr = any as? [Any] { arr.forEach { walk($0, visit) }; return }
        guard let d = any as? [String: Any] else { return }
        visit(d)
        for key in ["@graph", "itemListElement", "item", "subEvent", "event", "events"] {
            if let v = d[key] { walk(v, visit) }
        }
    }

    static func event(from d: [String: Any], base: URL) -> ICSEvent? {
        let types: [String] = (d["@type"] as? [String]) ?? [(d["@type"] as? String) ?? ""]
        guard types.contains(where: { $0.hasSuffix("Event") }),
              let name = d["name"] as? String,
              let startRaw = d["startDate"] as? String,
              let (start, allDay) = isoDate(startRaw) else { return nil }
        if let status = d["eventStatus"] as? String, status.contains("Cancelled") { return nil }
        let end = (d["endDate"] as? String).flatMap(isoDate)?.0
        var location = ""
        var lat: Double?, lon: Double?
        let locs: [[String: Any]] = (d["location"] as? [[String: Any]]) ?? ((d["location"] as? [String: Any]).map { [$0] } ?? [])
        if let loc = locs.first {
            var parts: [String] = []
            if let n = loc["name"] as? String { parts.append(n) }
            if let a = loc["address"] as? String { parts.append(a) }
            if let a = loc["address"] as? [String: Any] {
                parts += ["streetAddress", "addressLocality", "addressRegion"].compactMap { a[$0] as? String }
            }
            var unique: [String] = []
            for p in parts.map({ decodeEntities($0).trimmingCharacters(in: .whitespaces) }) where !p.isEmpty && !unique.contains(p) {
                unique.append(p)
            }
            location = unique.joined(separator: ", ")
            if let g = loc["geo"] as? [String: Any] {
                lat = number(g["latitude"]); lon = number(g["longitude"])
            }
        } else if let s = d["location"] as? String {
            location = s
        }
        if let mode = d["eventAttendanceMode"] as? String, mode.contains("Online") { return nil }
        let url = (d["url"] as? String).map { absolute($0, base: base) }
        return ICSEvent(uid: url ?? "\(name)-\(startRaw)", title: decodeEntities(name), start: start, end: end,
                        allDay: allDay, location: location,
                        notes: decodeEntities((d["description"] as? String) ?? ""),
                        url: url, latitude: lat, longitude: lon)
    }

    static func number(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let s = any as? String { return Double(s) }
        if let n = any as? NSNumber { return n.doubleValue }
        return nil
    }

    static func isoDate(_ s: String) -> (Date, Bool)? {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.count == 10 {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone.current
            f.dateFormat = "yyyy-MM-dd"
            return f.date(from: t).map { ($0, true) }
        }
        let iso = ISO8601DateFormatter()
        for opts: ISO8601DateFormatter.Options in [[.withInternetDateTime], [.withInternetDateTime, .withFractionalSeconds]] {
            iso.formatOptions = opts
            if let d = iso.date(from: t) { return (d, false) }
        }
        // No time zone given: read it as local time.
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        for p in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm"] {
            f.dateFormat = p
            if let d = f.date(from: t) { return (d, false) }
        }
        return nil
    }

    // MARK: - RSS and Atom

    static func parseFeed(_ xml: String) -> [PostItem] {
        let reader = FeedXMLReader()
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = reader
        parser.parse()
        return reader.items
    }

    // MARK: - XenForo forums (NetRider and many others)

    struct ThreadRef { var id: String; var title: String; var url: String; var started: Date? }

    static func xenForoThreads(_ html: String, base: URL) -> [ThreadRef] {
        var out: [ThreadRef] = []
        let chunks = html.components(separatedBy: #"<div class="structItem structItem--thread"#).dropFirst()
        for c in chunks {
            guard let href = firstMatch(#"<a href="([^"]*/threads/[^"]+)"[^>]*data-tp-primary="on""#, in: c),
                  let rawTitle = firstMatch(#"data-tp-primary="on"[^>]*>(.*?)</a>"#, in: c) else { continue }
            let url = absolute(href, base: base)
            let id = firstMatch(#"\.(\d+)/?$"#, in: href) ?? href
            let started = firstMatch(#"<time[^>]*datetime="([^"]+)""#, in: c).flatMap(isoDate)?.0
            out.append(ThreadRef(id: id, title: plainText(rawTitle), url: url, started: started))
        }
        return out
    }

    /// Links to XenForo calendar events (/events/name.123/) on a page.
    static func xenForoEventLinks(_ html: String, base: URL) -> [String] {
        var seen = Set<String>()
        return allMatches(#"href="((?:https?://[^"/]+)?/events/[a-z0-9-]+\.\d+/)""#, in: html)
            .map { absolute($0, base: base) }
            .filter { seen.insert($0).inserted }
    }

    static func firstPostText(_ html: String) -> String {
        guard let body = firstMatch(#"<div class="bbWrapper">(.*?)(?:<div class="js-selectToQuoteEnd|</article>)"#, in: html) else { return "" }
        return plainText(body)
    }

    // MARK: - Helpers

    static func plainText(_ html: String) -> String {
        var s = html.replacingOccurrences(of: #"<br\s*/?>|</p>|</div>"#, with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        s = decodeEntities(s)
        s = s.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\n\s*\n+"#, with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Notes for showing to a person: forum codes like [SIZE=5] or [USER=1]name[/USER] taken out.
    static func readableNotes(_ s: String) -> String {
        s.replacingOccurrences(of: #"\[/?[A-Za-z]+(=[^\]]*)?\]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = s
        for (k, v) in ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#039;": "'", "&#39;": "'", "&apos;": "'", "&nbsp;": " "] {
            out = out.replacingOccurrences(of: k, with: v)
        }
        while let r = out.range(of: #"&#x?[0-9a-fA-F]+;"#, options: .regularExpression) {
            let code = out[r].dropFirst(2).dropLast()
            let value = code.hasPrefix("x") || code.hasPrefix("X") ? UInt32(code.dropFirst(), radix: 16) : UInt32(code)
            out.replaceSubrange(r, with: value.flatMap(UnicodeScalar.init).map { String(Character($0)) } ?? "")
        }
        return out
    }

    static func firstMatch(_ pattern: String, in s: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }

    static func allMatches(_ pattern: String, in s: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return [] }
        return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap {
            Range($0.range(at: 1), in: s).map { String(s[$0]) }
        }
    }
}

enum DiscoverError: LocalizedError {
    case nothingFound
    var errorDescription: String? {
        "RollCall couldn't find any events, a calendar link or a news feed on that page."
    }
}

final class FeedXMLReader: NSObject, XMLParserDelegate {
    var items: [PostItem] = []
    private var current: [String: String]?
    private var element = ""
    private var buffer = ""

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        let n = name.lowercased()
        if n == "item" || n == "entry" { current = [:] }
        if n == "link", current != nil, let href = attributes["href"],
           attributes["rel"] == nil || attributes["rel"] == "alternate" {
            current?["link"] = href  // Atom
        }
        element = n
        buffer = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { buffer += string }

    func parser(_ parser: XMLParser, foundCDATA block: Data) {
        buffer += String(decoding: block, as: UTF8.self)
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let n = name.lowercased()
        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if n == "item" || n == "entry", let c = current {
            let link = c["link"] ?? ""
            let dateStr = c["pubdate"] ?? c["published"] ?? c["updated"] ?? c["dc:date"] ?? ""
            items.append(PostItem(id: c["guid"] ?? c["id"] ?? link,
                                  title: Web.plainText(c["title"] ?? ""),
                                  link: link,
                                  published: FeedXMLReader.date(dateStr),
                                  text: Web.plainText(c["content:encoded"] ?? c["content"] ?? c["description"] ?? c["summary"] ?? "")))
            current = nil
        } else if current != nil, !text.isEmpty {
            if n == "link", current?["link"] != nil { return }
            current?[n] = text
        }
        buffer = ""
    }

    static func date(_ s: String) -> Date? {
        if s.isEmpty { return nil }
        if let (d, _) = Web.isoDate(s) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for p in ["EEE, dd MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm:ss zzz"] {
            f.dateFormat = p
            if let d = f.date(from: s) { return d }
        }
        return nil
    }
}

