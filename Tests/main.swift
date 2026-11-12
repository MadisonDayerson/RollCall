import Foundation
import CoreLocation

var failures = 0
func check(_ cond: Bool, _ msg: String, line: Int = #line) {
    if cond { print("ok   \(msg)") } else { print("FAIL \(msg) (line \(line))"); failures += 1 }
}
let mel = TimeZone(identifier: "Australia/Melbourne")!
var cal = Calendar(identifier: .gregorian); cal.timeZone = mel
func comps(_ d: Date) -> DateComponents { cal.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: d) }
let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 9))!

// Facebook-style single event export
let fb = """
BEGIN:VCALENDAR\r
VERSION:2.0\r
PRODID:Facebook\r
BEGIN:VEVENT\r
DTSTAMP:20261101T000000Z\r
LAST-MODIFIED:20261101T000000Z\r
CREATED:20261101T000000Z\r
SEQUENCE:0\r
ORGANIZER;CN=Yarra Valley Riders:MAILTO:noreply@facebookmail.com\r
DTSTART:20261108T223000Z\r
DTEND:20261109T040000Z\r
UID:e1122334455667788@facebook.com\r
SUMMARY:Sunday breakfast run\\, Black Spur\r
LOCATION:Shell Coldstream\\, 2470 Maroondah Hwy\\, Coldstream VIC\r
URL:https://www.facebook.com/events/1122334455667788/\r
DESCRIPTION:Meet 9am. Corner marker system.\\nFull tank please.\r
 Long line continues here.\r
BEGIN:VALARM\r
TRIGGER:-PT1H\r
DESCRIPTION:Reminder\r
END:VALARM\r
CLASS:PUBLIC\r
END:VEVENT\r
END:VCALENDAR\r
"""
let fbEvents = ICSParser.parse(fb, now: now)
check(fbEvents.count == 1, "facebook export gives one event")
if let e = fbEvents.first {
    check(e.title == "Sunday breakfast run, Black Spur", "title unescaped: \(e.title)")
    check(e.location == "Shell Coldstream, 2470 Maroondah Hwy, Coldstream VIC", "location unescaped")
    check(e.notes.contains("\nFull tank") && e.notes.contains("please.Long line"), "description unfolded")
    let c = comps(e.start)
    check(c.day == 9 && c.hour == 9 && c.minute == 30, "UTC start converted to Melbourne time (9:30am Sun 9 Nov)")
    check(Store.eventID(source: "file", item: e) == "facebook:1122334455667788", "facebook id from url")
}
check(Store.facebookEventID("https://www.facebook.com/events/s/sunday-run/987654321012/?mibextid=abc") == "987654321012", "id from share-style link")
check(Store.facebookEventID("https://m.facebook.com/events/123456789012") == "123456789012", "id from mobile link")
check(Store.facebookEventID("https://www.facebook.com/groups/12345678") == nil, "group link is not an event")

// Meetup-style with TZID and GEO
let meetup = """
BEGIN:VCALENDAR
BEGIN:VEVENT
UID:event_316000001@meetup.com
SUMMARY:Great Ocean Road day ride
DTSTART;TZID=Australia/Melbourne:20261115T083000
DTEND;TZID=Australia/Melbourne:20261115T170000
GEO:-38.1499;144.3617
LOCATION:Geelong Waterfront (Cunningham Pier\\, Geelong\\, AU)
URL:https://www.meetup.com/motorcycle-riders-vic/events/316000001/
END:VEVENT
BEGIN:VEVENT
UID:cancelled@meetup.com
STATUS:CANCELLED
SUMMARY:Cancelled ride
DTSTART:20261116T000000Z
END:VEVENT
END:VCALENDAR
"""
let m = ICSParser.parse(meetup, now: now)
check(m.count == 1, "cancelled events dropped")
if let e = m.first {
    check(comps(e.start).hour == 8 && comps(e.start).minute == 30, "TZID time kept")
    check(e.latitude == -38.1499 && e.longitude == 144.3617, "GEO read")
}

// Club calendar: second Sunday each month, weekly Wednesday night ride with an exception
let club = """
BEGIN:VCALENDAR
BEGIN:VEVENT
UID:monthly@club
SUMMARY:Club run
DTSTART;TZID=Australia/Melbourne:20260111T090000
DURATION:PT6H
RRULE:FREQ=MONTHLY;BYDAY=2SU
END:VEVENT
BEGIN:VEVENT
UID:weekly@club
SUMMARY:Wednesday night ride
DTSTART;TZID=Australia/Melbourne:20261007T190000
DTEND;TZID=Australia/Melbourne:20261007T210000
RRULE:FREQ=WEEKLY;BYDAY=WE;UNTIL=20261231T000000Z
EXDATE;TZID=Australia/Melbourne:20261111T190000
END:VEVENT
BEGIN:VEVENT
UID:allday@club
SUMMARY:Rally weekend
DTSTART;VALUE=DATE:20261121
DTEND;VALUE=DATE:20261123
END:VEVENT
END:VCALENDAR
"""
let c = ICSParser.parse(club, horizon: 60, now: now)
let monthly = c.filter { $0.title == "Club run" }
check(monthly.count == 2, "2nd-Sunday rule within 60 days gives Nov + Dec (\(monthly.count))")
if let f = monthly.first {
    let fc = comps(f.start)
    check(fc.month == 11 && fc.day == 8 && fc.weekday == 1 && fc.hour == 9, "first is Sun 8 Nov 9am")
    check(f.end == f.start.addingTimeInterval(6 * 3600), "DURATION applied")
}
let weekly = c.filter { $0.title == "Wednesday night ride" }
check(weekly.allSatisfy { comps($0.start).weekday == 4 && comps($0.start).hour == 19 }, "weekly on Wednesdays 7pm")
check(!weekly.contains { comps($0.start).month == 11 && comps($0.start).day == 11 }, "EXDATE skipped")
check(weekly.count == 8, "Wednesdays 4 Nov–30 Dec minus one = 8 (\(weekly.count))")
check(Set(weekly.map(\.uid)).count == weekly.count, "occurrences have distinct ids")
check(c.first { $0.title == "Rally weekend" }?.allDay == true, "all-day event")

// Feed links
check(FeedLinks.normalise("https://www.meetup.com/en-AU/motorcycle-riders-vic/events/123/")?.url
      == "https://www.meetup.com/motorcycle-riders-vic/events/ical/", "meetup page -> ical feed")
check(FeedLinks.normalise("webcal://example.org/cal.ics")?.url == "https://example.org/cal.ics", "webcal -> https")
check(FeedLinks.normalise("https://www.facebook.com/groups/123") == nil, "facebook isn't a feed")
check(FeedLinks.normalise("x.org/a.ics")?.id == FeedLinks.normalise("x.org/a.ics")?.id, "feed ids are stable")

// Store: distance filter, merge, prune
let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("motorides-test-\(UUID()).json")
let store = Store(file: tmp)
store.state.events = [:]
store.merge(m, source: "meetup-x", sourceName: "X", now: now)
let far = ICSEvent(uid: "far", title: "Far ride", start: now.addingTimeInterval(86400 * 3), end: nil, allDay: false,
                   location: "Mildura", notes: "", url: nil, latitude: -34.18, longitude: 142.16)
store.merge([far], source: "meetup-x", sourceName: "X", now: now)
let up = store.upcoming(now: now)
check(up.count == 1 && up[0].title == "Great Ocean Road day ride", "far ride (Mildura) hidden, Geelong shown")
check(abs((up.first?.distanceKm ?? 0) - 64) < 10, "Geelong about 64 km from CBD (\(Int(up.first?.distanceKm ?? 0)))")
let later = now.addingTimeInterval(3600)
store.merge(Array(m.prefix(0)), source: "meetup-x", sourceName: "X", now: later)
store.prune(refreshedSources: ["meetup-x"], refreshStarted: later, now: later)
check(store.state.events.isEmpty, "rides that vanished from their feed are dropped")
store.merge(m, source: "meetup-x", sourceName: "X", now: now)
store.state.decisions["meetup-x:event_316000001@meetup.com"] = .attending
store.prune(refreshedSources: ["meetup-x"], refreshStarted: later, now: later)
check(store.state.events.count == 1, "...unless you're attending")
let monthOn = now.addingTimeInterval(40 * 86400)
check(store.past(now: monthOn).map(\.id) == ["meetup-x:event_316000001@meetup.com"], "attended ride listed under past rides once it's over")
check(store.past(now: now).isEmpty, "...but not before")
let wentID = "meetup-x:event_316000001@meetup.com"
let over = store.state.events[wentID]!.finish
store.prune(refreshedSources: [], refreshStarted: over, now: over.addingTimeInterval(6 * 86400))
check(store.state.events[wentID] != nil && store.decision(wentID) == .attending, "a ride you went on stays under Past for the week Privacy keeps it")
store.prune(refreshedSources: [], refreshStarted: over, now: over.addingTimeInterval(8 * 86400))
check(store.state.events.isEmpty && store.state.decisions[wentID] == nil, "...then it's deleted")
store.merge(m, source: "meetup-x", sourceName: "X", now: now)
store.state.decisions[wentID] = .attending
store.state.settings.keepDismissedDays = 0
store.prune(refreshedSources: [], refreshStarted: over, now: over.addingTimeInterval(60))
check(store.state.events.isEmpty, "with Don't keep, a ride is deleted once it's over")
store.state.settings.keepDismissedDays = 30
check(store.state.settings.keepDays == 14, "nothing is kept longer than two weeks")
store.state.settings.keepDismissedDays = nil
store.state.recentPosts = ["f": [PostItem(id: "old", title: "", link: "", published: now.addingTimeInterval(-15 * 86400), text: "Made-up post"),
                                 PostItem(id: "new", title: "", link: "", published: now.addingTimeInterval(-86400), text: "Made-up post")]]
store.state.geocodeCache = ["long gone ride place": [0, 0]]
store.prune(refreshedSources: [], refreshStarted: now, now: now)
check(store.state.recentPosts["f"]?.map(\.id) == ["new"], "posts waiting to be looked at go after two weeks")
check(store.state.geocodeCache.isEmpty, "places are forgotten once no ride is there")
store.merge(m, source: "meetup-x", sourceName: "X", now: now)
store.state.decisions["meetup-x:event_316000001@meetup.com"] = .attending
store.save()
check(Store(file: tmp).state.decisions.count == 1, "state saves and reloads")
try? FileManager.default.removeItem(at: tmp)


// MARK: - New sources

// Date/time/place in an Instagram-style caption
let caption = """
🏍️ HOOLIGOON RIDE OUT 🏍️
Sunday 8 November 2026, meet 8:30am at 2470 Maroondah Highway, Coldstream VIC 3770
All bikes welcome #ride #melbourne
"""
let cap = TextDetect.scan(caption, now: now)
check(cap.start.map { comps($0).day == 8 && comps($0).hour == 8 && comps($0).minute == 30 } ?? false, "caption date+time found")
check(cap.hasTime, "caption has a time")
check(cap.address?.contains("Coldstream") ?? false, "caption address found: \(cap.address ?? "nil")")
check(TextDetect.title(from: caption).contains("RIDE OUT"), "title from first line")
let dateOnly = TextDetect.scan("Bike night on Saturday 14 November 2026, Customs Lawn", now: now)
check(dateOnly.start.map { comps($0).day == 14 && comps($0).hour == 0 } ?? false && !dateOnly.hasTime, "date without time -> all day")
check(TextDetect.scan("What a ride that was on 3 October 2026!", now: now).start == nil, "past dates ignored")
// Times without am/pm are read as written, whatever the clock says when the test runs.
check(TextDetect.scan("Saturday 14 November 2026, kickstands up 7:45", now: now).start.map { comps($0).hour == 7 && comps($0).minute == 45 } == true, "7:45 with no am/pm is the morning")
check(TextDetect.scan("Saturday 14 November 2026, meet 2:30", now: now).start.map { comps($0).hour == 14 && comps($0).minute == 30 } == true, "2:30 with no am/pm is the afternoon")
check(TextDetect.scan("Saturday 14 November 2026, meet 8:30pm", now: now).start.map { comps($0).hour == 20 } == true, "pm when written")

// Ride words
check(RideWords.matches("Sikh motorcycle club annual dinner", strict: true), "strict: motorcycle")
check(!RideWords.matches("Motov8ing Boys", strict: true), "strict: whole words only")
check(!RideWords.matches("Riddim Riders", strict: true), "strict: 'riders' alone isn't enough")
check(RideWords.matches("Sunday ride to Marysville", strict: false), "loose: ride")
check(!RideWords.matches("WorldSBK - Round 3 - The Netherlands", strict: false), "race-watching thread isn't a ride")

// schema.org events in a page
let page = """
<html><head><title>Club events</title>
<script type="application/ld+json">{"@context":"https://schema.org","@graph":[
 {"@type":"Organization","name":"Club"},
 {"@type":"Event","name":"Toy Run 2026","startDate":"2026-12-06T09:00:00+11:00","endDate":"2026-12-06T13:00:00+11:00",
  "url":"/events/toy-run","location":{"@type":"Place","name":"Ringwood Lake","address":{"@type":"PostalAddress","streetAddress":"Maroondah Hwy","addressLocality":"Ringwood","addressRegion":"VIC"},
  "geo":{"latitude":"-37.81","longitude":145.23}}},
 {"@type":"Event","name":"Cancelled ride","startDate":"2026-12-07","eventStatus":"https://schema.org/EventCancelled"},
 {"@type":"Event","name":"Online talk","startDate":"2026-12-08","eventAttendanceMode":"https://schema.org/OnlineEventAttendanceMode"}
]}</script>
<script type="application/ld+json">[{"@type":"ItemList","itemListElement":[{"@type":"ListItem","item":{"@type":["Event","SocialEvent"],"name":"Bike night &amp; BBQ","startDate":"2026-11-20","location":"Customs Lawn, Geelong"}}]}]</script>
</head></html>
"""
let base = URL(string: "https://club.example.org/whats-on/")!
let ld = Web.jsonLDEvents(page, base: base)
check(ld.count == 2, "two live events (cancelled and online dropped): \(ld.map(\.title))")
if let t = ld.first(where: { $0.title == "Toy Run 2026" }) {
    check(comps(t.start).hour == 9 && !t.allDay, "event time with offset")
    check(t.location == "Ringwood Lake, Maroondah Hwy, Ringwood, VIC", "place joined: \(t.location)")
    check(t.latitude == -37.81 && t.longitude == 145.23, "geo read from strings and numbers")
    check(t.url == "https://club.example.org/events/toy-run", "relative url made absolute")
}
check(ld.first { $0.title == "Bike night & BBQ" }?.allDay == true, "date-only event, entity decoded, array @type")
check(Web.pageTitle(page) == "Club events", "page title")
check(Web.calendarLink(#"<a href="/events/?ical=1">Export</a>"#, base: base) == "https://club.example.org/events/?ical=1", "finds ?ical=1 links")
check(Web.calendarLink(#"<a href="webcal://cal.example.org/rides.ics">Sub</a>"#, base: base) == "https://cal.example.org/rides.ics", "finds webcal links")

// RSS and Atom
let rss = """
<?xml version="1.0"?><rss version="2.0"><channel><title>Blog</title>
<item><title>Ride out this Sunday</title><link>https://b.example/ride</link><guid>r1</guid>
<pubDate>Sat, 31 Oct 2026 10:00:00 +1100</pubDate><description><![CDATA[<p>Meet at <b>Kew</b> 9am</p>]]></description></item>
</channel></rss>
"""
let posts = Web.parseFeed(rss)
check(posts.count == 1 && posts[0].title == "Ride out this Sunday" && posts[0].link == "https://b.example/ride", "rss item")
check(posts.first?.text == "Meet at Kew 9am", "rss html stripped")
check(posts.first?.published != nil, "rss date")
let atom = """
<feed xmlns="http://www.w3.org/2005/Atom"><entry><title>New drop</title><link rel="alternate" href="https://shop.example/blogs/news/drop"/>
<id>tag:1</id><published>2026-10-30T10:00:00+11:00</published><summary>Hats</summary></entry></feed>
"""
let ap = Web.parseFeed(atom)
check(ap.first?.link == "https://shop.example/blogs/news/drop" && ap.first?.id == "tag:1", "atom entry")

// XenForo forum listing
let xf = """
<div class="structItem structItem--thread is-unread js-inlineModContainer" data-author="a">
 <div class="structItem-title"><a href="/threads/sunday-ride-to-marysville.288001/" class="" data-tp-primary="on" data-xf-init="preview-tooltip">Sunday ride to Marysville</a></div>
 <li class="structItem-startDate"><a href="/threads/sunday-ride-to-marysville.288001/" rel="nofollow"><time  class="u-dt" datetime="2026-10-30T20:00:00+1100">Oct 30</time></a></li>
</div>
<div class="structItem structItem--thread js-inlineModContainer">
 <a href="/threads/geelong-bike-night.287947/" data-tp-primary="on">Geelong &amp; Surf Coast bike night</a>
 <time datetime="2026-09-30T10:02:31+1000"></time>
 <a href="/events/geelong-october-bike-night.3257/">event</a>
</div>
"""
let xfBase = URL(string: "https://netrider.net.au/forum/vic.69/")!
let threads = Web.xenForoThreads(xf, base: xfBase)
check(threads.count == 2, "two threads")
check(threads.first?.id == "288001" && threads.first?.url == "https://netrider.net.au/threads/sunday-ride-to-marysville.288001/", "thread id and url")
check(threads.last?.title == "Geelong & Surf Coast bike night", "thread title decoded")
check(Web.isXenForo(xf), "recognised as a XenForo forum")
check(Web.xenForoEventLinks(xf, base: xfBase) == ["https://netrider.net.au/events/geelong-october-bike-night.3257/"], "event link found")
let viaThread = ICSEvent(uid: "3257", title: "x", start: now, end: nil, allDay: false, location: "", notes: "",
                         url: "https://netrider.net.au/events/geelong-october-bike-night.3257/")
check(Store.eventID(source: "netrider-vic-forum", item: viaThread) == Store.eventID(source: "netrider-events", item: viaThread),
      "same forum event from two sections gets one id")
check(Web.firstPostText(#"<div class="bbWrapper">Meet <b>9am</b><br />Sat 7 Nov</div><div class="js-selectToQuoteEnd">"#) == "Meet 9am\nSat 7 Nov", "first post text")

// Older save files keep their choices and pick up the new starter sources
let oldFile = FileManager.default.temporaryDirectory.appendingPathComponent("motorides-old-\(UUID()).json")
try! """
{"settings":{"homeName":"Melbourne","homeLatitude":-37.8136,"homeLongitude":144.9631,"radiusKm":80,"daysAhead":60,"watchDownloads":true},
 "feeds":[{"id":"meetup-motorcycle-riders-vic","name":"Motorcycle Riders VIC (Meetup)","url":"https://www.meetup.com/motorcycle-riders-vic/events/ical/"}],
 "events":{},"decisions":{"x":"attending"},"calendarItems":{"x":"cal-1"},"facebookGroups":{},"geocodeCache":{},"feedErrors":{}}
""".write(to: oldFile, atomically: true, encoding: .utf8)
let migrated = Store(file: oldFile).state
check(migrated.decisions["x"] == .attending && migrated.calendarItems["x"] == "cal-1", "old choices kept")
check(migrated.settings.radiusKm == 80, "old settings kept")
check(migrated.feeds.count == Starter.feeds.count && migrated.feeds.contains { $0.id == "netrider-vic-forum" }, "new starter sources added")
check(migrated.instagram.map(\.handle) == ["hooligoon.co"], "hooligoon.co added to Instagram list")
check(migrated.feeds[0].type == .calendar, "old feeds read as calendar feeds")
try? FileManager.default.removeItem(at: oldFile)

// Beeper chats
let beeperJSON = """
{"items":[
 {"id":"m1","chatID":"!abc:beeper.com","accountID":"whatsapp","senderID":"@x","senderName":"Dave","timestamp":"2026-10-31T09:15:00.000Z","sortKey":"1","type":"TEXT",
  "text":"Sunday ride: Kinglake loop. Meet Sunday 8 November at 8:30am, Shell Coldstream, 2470 Maroondah Hwy, Coldstream VIC"},
 {"id":"m2","chatID":"!abc:beeper.com","accountID":"whatsapp","senderID":"@y","timestamp":"2026-10-31T09:16:00Z","sortKey":"2","type":"REACTION","text":"👍"},
 {"id":"m3","chatID":"!abc:beeper.com","accountID":"whatsapp","senderID":"@y","timestamp":"2026-10-31T09:17:00Z","sortKey":"3","type":"TEXT","text":"keen!"},
 {"id":"m4","chatID":"!abc:beeper.com","accountID":"whatsapp","senderID":"@z","senderName":"Sam","timestamp":"2026-10-31T10:00:00Z","sortKey":"4","type":"TEXT",
  "text":"Who's going to this? https://www.facebook.com/events/998877665544/ bike night","links":[{"url":"https://www.facebook.com/events/998877665544/"}]}
],"hasMore":false,"oldestCursor":"a","newestCursor":"b"}
"""
struct BeeperPage: Decodable { var items: [Beeper.Message] }
let msgs = try! JSONDecoder().decode(BeeperPage.self, from: Data(beeperJSON.utf8)).items
check(msgs.count == 4 && msgs[0].date != nil && msgs[1].date != nil, "Beeper messages decode, with and without fractional seconds")
let p1 = SourceReader.chatPost(msgs[0], chatID: "!abc:beeper.com")
check(p1?.title.hasPrefix("Dave: Sunday ride") == true, "chat post titled with the sender")
check(p1?.link == "beeper-chat:!abc:beeper.com#m1", "chat post links back to the message in Beeper")
check(SourceReader.chatPost(msgs[1], chatID: "x") == nil, "reactions ignored")
check(SourceReader.chatPost(msgs[2], chatID: "x") == nil, "one-word replies ignored")
check(SourceReader.chatPost(msgs[3], chatID: "x")?.link == "https://www.facebook.com/events/998877665544/", "shared Facebook event link preferred")
let chatFeed = Beeper.feed(for: Beeper.Chat(id: "!abc:beeper.com", title: "Sunday Riders", network: "WhatsApp", type: "group"))
check(chatFeed.name == "Sunday Riders (WhatsApp via Beeper)" && chatFeed.type == .chat && Beeper.chatID(of: chatFeed) == "!abc:beeper.com", "chat feed")
let oneLine = PlanFinder.line(from: p1!, sender: "Dave")
let single = PlanFinder.find([oneLine], newIDs: ["m1"], feedID: chatFeed.id, chatID: "!abc:beeper.com", now: now).first?.summary
check(single.map { $0.start.map { comps($0).day == 8 && comps($0).hour == 8 && comps($0).minute == 30 } == true } == true, "plan date read from chat message")
check(single?.title.hasPrefix("Sunday ride") == true, "plan title without the sender")
check(single?.place?.contains("Coldstream") == true, "meeting place from chat message")
check(SourceReader.chatPost(Beeper.Message(id: "h", chatID: "c", senderName: "@discordgo_1:beeper.local", timestamp: "2026-11-01T00:00:00Z",
                                           type: "TEXT", text: "Plus you can mod the MT<br>Just my 2c &amp; all"), chatID: "c")
      .map { $0.text == "Plus you can mod the MT\nJust my 2c & all" && !$0.title.contains("@discordgo") } == true,
      "chat text cleaned of HTML, internal sender ids left out")

// Planned rides versus chat. `now` is Sunday 1 Nov 2026, 9am.
func sentAt(_ day: Int, _ hour: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: day < 15 ? 11 : 10, day: day, hour: hour))! }
var planCal = Calendar.current; planCal.timeZone = mel
func judge(_ s: String, sent: Date = sentAt(1, 8)) -> RidePlan.Verdict { RidePlan.judge(s, sent: sent, now: now, calendar: planCal) }
let planned: [(String, Int, Int?)] = [   // message, day of month, hour (nil = all day)
    ("Thinking about going for a ride this arvo/evening. Anyone want to join? Have no destination set.", 1, 14),
    ("Who's keen for a ride Saturday? Meet at Shell Coldstream 9am, heading up the Black Spur", 7, 9),
    ("Sunday 8 Nov brekkie run to Marysville, kickstands up 8:30 from Lilydale Maccas", 8, 8),
    ("Anyone up for a blat tomorrow arvo?", 2, 14),
    ("Ride's on this Sunday! Meeting at the Kinglake bakery 10am, all welcome", 1, 10),
    ("We're heading out to Healesville on Wednesday around 6pm if anyone wants to come along", 4, 18),
    ("Planning a run down to Phillip Island on 15/11, leaving from Dandenong Bunnings at 8", 15, 8),
    ("Bike night at Thomastown this Friday 7.30pm, who's coming?", 6, 19),
    ("Group ride Saturday 14 November, route is Reefton Spur loop", 14, nil),
]
for (msg, day, hour) in planned {
    let v = judge(msg)
    let ok = v.kind == .ride && v.start.map { comps($0).day == day && (hour == nil ? !v.hasTime : comps($0).hour == hour) } == true
    check(ok, "planned ride: \(msg.prefix(45))… → \(v.why), \(v.start.map { "\(comps($0).day!)/\(comps($0).hour!)" } ?? "no date")")
}
let notPlanned = [
    "Daughter all ready for trick or treating, now to eat an early dinner before taking her out, hope those girlies out riding tonight have a great time",
    "I (almost) dropped my bike taking it round the street",
    "ride down the m1 at 60 and mow the lawns right",
    "We have a ride on its just stashed down the road at other house 🤣",
    "Have a dope costume too would love to ride out in it",
    "The issue is selling a bike ive owned since new to then get a 2nd hand version",
    "Could probably get an older MT & an older lams bike for the price of a R7",
    "Great ride today everyone, thanks for coming! Pics from the Spur below",
    "Went for a ride to Kinglake yesterday, roads were wet",
    "Selling my Kriega bag, $120, pick up Brunswick, can bring it to Sunday's meet",
    "I'm in the west. Happy to ride anywhere.",
    "Weather is awesome. Sun is out! Videographer here, bikes pulling up now - get down here!!! 12 Smith Street, Collingwood VIC 3066",
    "Last Sunday's run was epic, same again next month?",
    "sat in the garage all arvo fixing the chain",
    "Is anyone close to Glen Waverley that can help pick my bike up for me at home?",
    "We have a ride on its just stashed down the road at other house 🤣",
    "This is the video from yesterday’s ride",
    "run the sumo down too",
]
for msg in notPlanned {
    let v = judge(msg, sent: msg.contains("Videographer") || msg.contains("trick") ? sentAt(31, 19) : sentAt(1, 8))
    check(v.kind != .ride, "not a planned ride: \(msg.prefix(45))… (\(v.why))")
}
check(judge("Anyone keen for a ride next weekend?").kind == .ride, "\"next weekend\" counts as a day")
check(judge("Anyone keen for a ride soon?").kind == .maybe, "invite with no day goes to Posts to look at")
check(judge("Ride Sunday, meet at Shell Coldstream 9am", sent: sentAt(25, 9)).kind == .no, "\"Sunday\" in last week's message is over")
let laterOn = judge("A couple of us were thinking about heading out a bit later on, could meet somewhere?", sent: sentAt(1, 8))
check(laterOn.kind == .ride && laterOn.hasTime && laterOn.start.map { comps($0).hour == 10 } == true, "\"a bit later\" means a couple of hours after the message")
check(judge("So nervous! We're going to meet him tonight, he's a 1 year old pup").kind == .no, "meeting someone isn't a ride")
check(judge("We're going to meet at the servo tonight, 7pm").kind == .ride, "meeting at a place still is")
check(RidePlan.judge("heading out a bit later on, could meet somewhere?", sent: sentAt(1, 8), now: sentAt(1, 20), calendar: planCal).kind == .no,
      "\"a bit later\" ride is over by the evening")

// Conversations to review
func msgAt(_ id: String, _ who: String, _ day: Int, _ h: Int, _ m: Int, _ text: String) -> ChatLine {
    let sent = cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: h, minute: m))!
    return ChatLine(id: id, sender: who, sent: sent, text: text, mentionsWhen: PlanFinder.mentionsWhen(text))
}
let thread = [
    msgAt("a1", "Alex", 1, 8, 2, "Thinking about going for a ride this arvo/evening. Anyone want to join? Have no destination set."),
    msgAt("a2", "Jordan", 1, 8, 3, "A couple of us were thinking about heading out a bit later on, could meet somewhere?"),
    msgAt("a3", "Alex", 1, 8, 16, "I'm in the west. Happy to ride anywhere."),
    msgAt("a4", "Sam", 1, 8, 30, "Keen! How about meet at Shell Coldstream 2pm"),
    msgAt("a5", "Alex", 1, 8, 31, "Sounds good"),
    msgAt("b1", "Jo", 1, 14, 0, "nice bike! what tyres are those"),
    msgAt("c1", "Jo", 1, 18, 0, "dinner at 7pm tonight anyone?"),
]
check(thread.filter(\.mentionsWhen).map(\.id) == ["a1", "a2", "a4", "c1"], "messages naming a time or day spotted")
check(PlanFinder.conversations(thread).map(\.count) == [5, 1, 1], "quiet gaps split conversations")
let found = PlanFinder.find(thread, newIDs: Set(thread.map(\.id)), feedID: "beeper-x", chatID: "!x", now: now)
check(found.count == 1 && found.first?.lines.count == 5, "one conversation to review, with all its messages")
let plan = found.first?.summary
check(plan?.start.map { comps($0).day == 1 && comps($0).hour == 14 } == true && plan?.hasTime == true, "agreed time is the latest one (2pm)")
check(plan?.place?.contains("Shell Coldstream") == true, "meeting point from a reply")
check(plan?.who == ["Alex", "Sam"], "who's in: the proposer and people who said yes")
check(found.first?.id == "plan:beeper-x:a1" && found.first?.keyMessage?.id == "a4", "review id and the message to jump to")
check(PlanFinder.find(thread, newIDs: ["a3", "a5"], feedID: "x", chatID: "x", now: now).isEmpty, "not raised again unless a new message names a time")
check(PlanFinder.find(thread, newIDs: Set(thread.map(\.id)), feedID: "x", chatID: "x",
                      now: cal.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 20))!).isEmpty, "plans that are over aren't raised")

// Criteria: a possible plan has a day still to come, a time and a place; a partial one is missing some.
do {
    let base = PlanSummary(title: "Ride", when: "", start: nil, hasTime: false, place: nil, who: [], undecided: nil,
                           summary: "", isPlan: true, byAI: false)
    let soon = cal.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 14))!
    let morning = cal.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 9))!
    var p = base
    check(p.readiness(now: morning) == .partial(missing: ["day", "time", "place"]), "a ride with nothing settled is partial")
    p.start = soon; p.hasTime = true
    check(p.readiness(now: morning) == .partial(missing: ["place"]), "still needs a place")
    p.place = "Example Servo"
    check(p.readiness(now: morning) == .ready, "day, time and place make a possible plan")
    check(p.readiness(now: soon.addingTimeInterval(4 * 3600)) == nil, "a plan that's over isn't suggested")
    p.isPlan = false
    check(p.readiness(now: morning) == nil, "not a ride plan")
}
// Conversations keep growing as the details are settled (made-up messages).
do {
    let start = [msgAt("f1", "Alex", 2, 9, 0, "Ride Sunday anyone?"), msgAt("f2", "Sam", 2, 9, 5, "Keen")]
    let monday = cal.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 10))!
    var review = PlanFinder.find(start, newIDs: ["f1", "f2"], feedID: "x", chatID: "!x", now: monday)
    check(review.count == 1, "a ride on Sunday is raised")
    var r = review.removeFirst()
    r.updated = monday
    let later = start + [
        msgAt("f3", "Jo", 3, 19, 0, "anyone selling a helmet?"),
        msgAt("f4", "Alex", 4, 12, 0, "Let's meet at Example Servo, 9am"),
        msgAt("f5", "Sam", 4, 12, 4, "perfect"),
    ]
    let wed = cal.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 13))!
    var newlyFound = PlanFinder.find(later, newIDs: ["f3", "f4", "f5"], feedID: "x", chatID: "!x", now: wed)
    let grown = PlanFinder.followUps(later, newIDs: ["f3", "f4", "f5"], found: &newlyFound, existing: [r], now: wed)
    check(grown.first?.lines.map(\.id) == ["f1", "f2", "f4", "f5"], "the meeting place and time join the plan; unrelated chat doesn't")
    check(newlyFound.isEmpty, "the same plan isn't raised twice")
    check(grown.first?.summary.place?.contains("Example Servo") == true && grown.first?.summary.hasTime == true, "the plan now has its place and time")
    var quiet = r; quiet.updated = monday.addingTimeInterval(-10 * 86400)
    var none: [PlanReview] = []
    check(PlanFinder.followUps(later, newIDs: ["f4"], found: &none, existing: [quiet], now: wed).count == 1,
          "a plan quiet for days still takes a new time or place until its ride is over")
    var stale = quiet; stale.summary.start = nil
    check(PlanFinder.followUps(later, newIDs: ["f4"], found: &none, existing: [stale], now: wed).isEmpty,
          "old conversations with no day stop collecting")
    let monday9th = cal.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 12))!
    check(PlanFinder.followUps(later, newIDs: ["f4"], found: &none, existing: [quiet], now: monday9th).isEmpty,
          "a plan whose ride is over stops collecting")
}

// Chats are read from just before the last check, or two weeks back the first time.
do {
    let now = Date()
    check(SourceReader.chatReadFrom(lastChecked: nil, now: now) == now.addingTimeInterval(-14 * 86400), "first read goes back two weeks")
    check(SourceReader.chatReadFrom(lastChecked: now.addingTimeInterval(-3600), now: now) == now.addingTimeInterval(-4 * 3600),
          "later reads start a quiet gap before the last check")
    check(SourceReader.chatReadFrom(lastChecked: now.addingTimeInterval(-30 * 86400), now: now) == now.addingTimeInterval(-14 * 86400),
          "never more than two weeks back")
}

// A web listing that gives only the day keeps the time and place its event page gave (made-up event).
do {
    let day = cal.date(from: DateComponents(year: 2026, month: 11, day: 21))!
    let listed = ICSEvent(uid: "w1", title: "Example run", start: day, end: nil, allDay: true, location: "", notes: "", url: nil)
    var old = ride("Example run", "Full details from the event page")
    old.start = cal.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 9))!; old.allDay = false
    old.location = "Example Park"
    let kept = SourceReader.keepingDetails(listed, from: old)
    check(!kept.allDay && kept.start == old.start && kept.location == "Example Park" && kept.notes == old.notes,
          "a known event keeps its page's time, place and notes")
    var moved = listed; moved.start = cal.date(byAdding: .day, value: 1, to: day)!
    check(SourceReader.keepingDetails(moved, from: old).allDay, "a listing that moves to a new day wins")
}

let fallback = plan!
let aiReply = """
PLAN: yes
TITLE: Sunday arvo ride
WHEN: Sunday 1 November, 2pm
DATE: 2026-11-01 14:00
WHERE: Shell Coldstream
WHO: Alex, Sam
UNDECIDED: Nothing
SUMMARY: Alex suggested an afternoon ride and Sam proposed meeting at Shell Coldstream at 2pm, which Alex agreed to.
"""
let parsed = PlanSummariser.parse(aiReply, fallback: fallback, now: now)
check(parsed?.isPlan == true && parsed?.byAI == true && parsed?.title == "Sunday arvo ride", "model reply read")
check(parsed?.start.map { comps($0).hour == 14 } == true && parsed?.undecided == nil && parsed?.who == ["Alex", "Sam"], "model reply fields")
check(PlanSummariser.parse("PLAN: no\nSUMMARY: Just chat about tyres.", fallback: fallback, now: now)?.isPlan == false, "model can say it isn't a plan")
check(PlanSummariser.parse("Sorry, I can't help with that.", fallback: fallback, now: now) == nil, "a reply in the wrong format is ignored")
check(PlanSummariser.parse("PLAN: yes\nDATE: 2019-01-01 10:00\nSUMMARY: x", fallback: fallback, now: now)?.start == fallback.start, "a far-off date from the model isn't trusted")
// A busy chat that never goes quiet: only the messages around the plan are kept.
var busy: [ChatLine] = (0..<48).map { i in msgAt("z\(i)", "P\(i % 5)", 1, 0, 0, "chat about tyres and exhausts \(i)") }
for i in busy.indices { busy[i].sent = cal.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 1))!.addingTimeInterval(Double(i) * 600) }
busy[20] = ChatLine(id: "z20", sender: "Ana", sent: busy[20].sent, text: "Anyone keen for a ride tomorrow arvo? Meet at the Kinglake bakery", mentionsWhen: true)
busy[22] = ChatLine(id: "z22", sender: "Ben", sent: busy[22].sent, text: "I'm in!", mentionsWhen: false)
check(PlanFinder.conversations(busy).count == 1, "busy chat is one long conversation")
let busyPlans = PlanFinder.find(busy, newIDs: ["z20"], feedID: "x", chatID: "x", now: now)
check(busyPlans.count == 1 && (busyPlans.first?.lines.count ?? 99) <= 25 && busyPlans.first?.lines.first?.id == "z16",
      "only the messages around the plan are kept (\(busyPlans.first?.lines.count ?? 0))")
check(busyPlans.first?.summary.who == ["Ana", "Ben"] && busyPlans.first?.summary.isPlan == true, "who's in from replies after the plan")
check(PlanFinder.guess([msgAt("q", "Rev", 1, 8, 0, "Spent today making a book press for mrs")], now: now).isPlan == false,
      "without the model, a passing mention of today isn't raised")
check(PlanFinder.mentionsWhen("Anyone out riding around 8ish?"), "\"8ish\" counts as a time")
check(PlanSummariser.parse("PLAN: yes\nUNDECIDED: no\nSUMMARY: x", fallback: fallback, now: now)?.undecided == nil, "\"no\" means nothing is undecided")
let bikeNight = [msgAt("h1", "Robin", 1, 8, 0, "Halloween bikes and costumes tonight, get down here!!! 12 Smith Street, Collingwood VIC 3066"),
                 msgAt("h2", "Taylor", 1, 8, 5, "See you soon!")]
check(PlanFinder.find(bikeNight, newIDs: ["h1"], feedID: "x", chatID: "x", now: now).count == 1, "a bike event counts, not just rides")
check(PlanFinder.find([msgAt("t1", "Jo", 1, 8, 0, "dinner at 7pm tonight anyone?")], newIDs: ["t1"], feedID: "x", chatID: "x", now: now).isEmpty,
      "times without anything about bikes aren't raised")
check(judge("Anyone out riding around 8ish?", sent: sentAt(1, 8)).start.map { comps($0).hour == 20 || comps($0).hour == 8 } == true, "\"around 8ish\" read as a time today")
check(judge("Anyone out riding around 8ish?", sent: sentAt(1, 8)).kind == .ride, "\"anyone out riding\" is an invite")
check(PlanSummariser.parse("PLAN: yes\nWHERE: west\nSUMMARY: x", fallback: fallback, now: now)?.place == fallback.place, "\"west\" isn't a meeting place")
check(PlanSummariser.parse("PLAN: yes\nWHERE: Sunbury\nSUMMARY: x", fallback: fallback, now: now)?.place == "Sunbury", "a real place is kept")
check(RidePlan.judge("Anyone out riding around 8ish?", sent: sentAt(1, 15), now: sentAt(1, 15), calendar: planCal).start.map { comps($0).hour == 20 } == true, "a bare 8 sent in the afternoon means 8pm")
check(PlanSummariser.parse("PLAN: yes\nWHEN: 6pm\nDATE: 2026-11-01 18:00\nSUMMARY: x", fallback: fallback, now: now)?.start == fallback.start, "a time read from the messages beats the model's")
let premeet = [
    msgAt("p1", "Robin", 1, 7, 0, "🎃 HALLOWEEN PRE-MEET RIDE! 🏍️\n\nGet your costumes on and ride with the crew to our HOOLIGOON Halloween Bike Night!\n\n📅 Saturday 7th November.\n📍 45 Hoddle Street, Richmond\n⏰ Kickstands up 5:30pm"),
    msgAt("p2", "Morgan", 1, 7, 10, "Oh no I forgot to organise a costume for the ride"),
    msgAt("p3", "Taylor", 1, 7, 13, "Bummed that im missing this"),
]
check(premeet[0].mentionsWhen, "an emoji-laden announcement's date is spotted")
let premeetPlan = PlanFinder.find(premeet, newIDs: ["p1"], feedID: "x", chatID: "x", now: now).first?.summary
check(premeetPlan?.start.map { comps($0).day == 7 && comps($0).hour == 17 && comps($0).minute == 30 } == true, "announced date and kickstands-up time read")
check(premeetPlan?.place?.contains("Hoddle") == true, "announced meeting point read")
var vic = Settings(); vic.homeCity = "Ringwood"; vic.homeRegion = "VIC"; vic.homeCountry = "Australia"
check(Starter.suggestions(for: vic).feeds.count == Starter.feeds.count, "Victorians get the Victorian groups")
var nsw = Settings(); nsw.homeCity = "Newtown"; nsw.homeRegion = "NSW"; nsw.homeCountry = "Australia"
check(Starter.suggestions(for: nsw).feeds.first?.url == "https://www.eventbrite.com/d/australia--newtown/motorcycle/", "elsewhere gets an Eventbrite search for their city")
check(Starter.suggestions(for: Settings()).feeds.isEmpty, "no suggestions before the home area is found")
check(AppState().feeds.isEmpty && !AppState().setupDone, "new installs start empty, before setup")
func ride(_ title: String, _ notes: String = "", source: String = "manual") -> RideEvent {
    RideEvent(id: "r1", title: title, start: DateComponents(calendar: Calendar.current, year: 2026, month: 10, day: 31, hour: 17, minute: 30).date!,
              end: nil, allDay: false, location: "45 Hoddle Street, Richmond", notes: notes, url: nil,
              source: source, sourceName: "SUNDAY CREW", lastSeen: Date())
}
check(Crew.rideTags(ride("Halloween Pre-Meet Ride"))[0] == "#RC31102026", "ride code is RC and the date")
check(Crew.rideTags(ride("Halloween Pre-Meet Ride")) == ["#RC31102026", "#Halloween", "#Richmond"], "occasion and town tags follow the code")
check(Crew.rideTags(ride("HOOLIGOON TTR - STREET RUN")).filter { $0 != "#Halloween" }.dropFirst().prefix(2) == ["#Hooligoon", "#TTR"], "club names tamed, short acronyms kept, everyday words skipped")
check(Crew.rideTags(ride("Torque & Terror bike night")).contains("#TorqueTerror"), "names joined by & stay one tag")
check(Crew.rideTags(ride("Costume ride, win an Ace Pro 2")).contains("#insta360"), "brands get their own tag")
check(Crew.rideTags(ride("Krispy Kreme run to the Black Spur")).contains("#BlackSpur") && Crew.rideTags(ride("Krispy Kreme run")).contains("#KrispyKreme"), "places in the name become tags")
check(!Crew.rideTags(ride("Breakfast at Marysville with Sam")).contains("#Sam"), "people's names aren't tags")
check(Crew.placeTags("Kebab Shop, 12 Example St, Broadford VIC 3658, Australia") == ["#KebabShop", "#Broadford"], "venue and town from an address")
check(Crew.rideTags(ride("Sunday ride", "see you there #blackspur")).contains("#blackspur"), "tags in someone's invite are kept")
var crewT = Together(); crewT.tags = "hooligoon, #RollCall #melbriders"; crewT.discord = "https://discord.gg/abc"; crewT.intercomGroup = "DMC SUNDAY CREW"
let tagsOut = Crew.hashtags(ride("Halloween Pre-Meet Ride"), together: crewT, links: CrewLinks(tags: "#sundaycrew"))
check(tagsOut == ["#RC31102026", "#Halloween", "#Richmond", "#RollCall", "#sundaycrew", "#hooligoon", "#melbriders"], "tags: ride, app, group, yours, no repeats")
let card = Crew.card(ride("Halloween Pre-Meet Ride"), together: crewT, links: CrewLinks(discord: "https://discord.gg/group")).joined(separator: "\n")
check(card.contains("discord.gg/group") && !card.contains("discord.gg/abc"), "a group's Discord replaces yours")
check(card.contains("Cardo: DMC SUNDAY CREW") && card.contains("Find My") && card.contains("maps.apple.com/?q=45%20Hoddle"), "calendar card has intercom, location app and map")
check(Crew.key(forSource: "file") == "yours" && Crew.key(forSource: "facebook") == "facebook", "hand-added rides share crew settings")
check(Updater.isNewer("1.10", than: "1.9") && Updater.isNewer("v1.1", than: "1.0") && !Updater.isNewer("1.0", than: "1.0.0"), "version comparison")
check(Updater.isOurDownload("https://github.com/MadisonDayerson/RollCall/releases/download/v1.2.3/RollCall.dmg")
      && !Updater.isOurDownload("https://github.com/someone-else/rollcall/releases/download/v1/RollCall.dmg")
      && !Updater.isOurDownload("https://example.com/MadisonDayerson/rollcall/releases/download/v1/RollCall.dmg")
      && !Updater.isOurDownload("http://github.com/MadisonDayerson/rollcall/releases/download/v1/RollCall.dmg")
      && !Updater.isOurDownload("https://github.com/MadisonDayerson/rollcall/releases/download/v1/RollCall.zip"),
      "updates only download from RollCall's own GitHub releases")
check(RidePlan.place(in: "this is going to hurt me more then it will you") == nil, "lower-case words aren't a destination")

check(PlanSummariser.prompt(Array(thread.prefix(2)), chatName: "Sunday Crew").contains("Alex: Thinking about going for a ride"), "conversation goes into the prompt")
check(TextDetect.scan("ride this Sunday 9am", now: Date(), absoluteOnly: true).start == nil, "old message: 'this Sunday' ignored")
check(TextDetect.scan("ride Sunday 15 Nov 9am", now: Date(), absoluteOnly: true).start != nil, "old message: full date kept")
check(TextDetect.scan("ride this Sunday 9am", now: Date()).start != nil, "new message: 'this Sunday' used")
check(Beeper.pathPart("!abc:beeper.com") == "%21abc%3Abeeper.com", "chat id escaped for the URL")
check(Beeper.callbackQuery("GET /callback?code=xyz&state=s1 HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n") == ["code": "xyz", "state": "s1"], "OAuth callback read")
check(Beeper.callbackQuery("GET /favicon.ico HTTP/1.1\r\n\r\n") == nil, "other requests ignored")
let chatStore = Store(file: FileManager.default.temporaryDirectory.appendingPathComponent("motorides-chat-\(UUID()).json"))
chatStore.state.settings.radiusKm = 10
var farRide = ICSEvent(uid: "far", title: "Bright run", start: now.addingTimeInterval(86400 * 3), end: nil, allDay: true, location: "Bright", notes: "", url: nil)
farRide.latitude = -36.7; farRide.longitude = 146.96
_ = chatStore.merge([farRide], source: chatFeed.id, sourceName: chatFeed.name, needsCheck: true, now: now)
for k in chatStore.state.events.keys { chatStore.state.events[k]?.distanceKm = 230 }
check(chatStore.upcoming(now: now).count == 1, "rides from watched chats shown even when far away")

check(Web.readableNotes("[SIZE=5]Shindig in memory of [USER=25280]@fekkinell[/USER][/SIZE]") == "Shindig in memory of @fekkinell", "forum codes taken out of notes")

// How often each source is checked, and which app it's grouped under.
check(chatFeed.interval == 15 && chatFeed.app == "WhatsApp", "chats checked every 15 minutes, grouped by their app")
var renamed = chatFeed; renamed.network = nil
check(renamed.app == "WhatsApp", "older chat sources grouped by the app in their name")
renamed.name = "Ride crew"
check(renamed.app == "Beeper chats", "renamed older chats grouped under Beeper")
let forumFeed = Starter.feeds.first { $0.kind == .forum }!
check(forumFeed.interval == 360 && forumFeed.app == "NetRider", "forums checked every 6 hours, grouped by site")
check(Starter.feeds[0].interval == 180 && Starter.feeds[0].app == "Meetup", "calendars every 3 hours")
check(Feed(id: "x", name: "Club", url: "https://example.org/rides", kind: .webpage).app == "Websites", "unknown sites grouped as Websites")
let tenAgo = now.addingTimeInterval(-600), twentyAgo = now.addingTimeInterval(-1200)
check(chatFeed.due(lastChecked: nil, lastTried: nil, now: now), "never-read source is due")
check(!chatFeed.due(lastChecked: tenAgo, lastTried: nil, now: now), "chat read 10 minutes ago isn't due")
check(chatFeed.due(lastChecked: twentyAgo, lastTried: nil, now: now), "chat read 20 minutes ago is due")
check(!chatFeed.due(lastChecked: twentyAgo, lastTried: tenAgo, now: now), "a failed try waits for the next slot too")
var manual = chatFeed; manual.every = 0
check(!manual.due(lastChecked: nil, lastTried: nil, now: now), "only-when-I-check sources are never automatic")
check(Feed.describe(15) == "Every 15 minutes" && Feed.describe(360) == "Every 6 hours" && Feed.describe(1440) == "Once a day", "interval names")

// Facebook share links (Share → Copy link) have no event number but open the event.
check(Store.facebookShareLink("https://www.facebook.com/share/1513oBi2LqL/") == "https://www.facebook.com/share/1513oBi2LqL/", "facebook share link accepted")
check(Store.facebookShareLink("facebook.com/share/e/1AbC9xYz") == "https://facebook.com/share/e/1AbC9xYz", "share link without https")
check(Store.facebookShareLink("https://m.facebook.com/share/1513oBi2LqL/?mibextid=abc") != nil, "mobile share link with tracking")
check(Store.facebookShareLink("https://fb.me/e/3xYzAbC") != nil, "fb.me event link")
check(Store.facebookShareLink("https://www.facebook.com/share/p/1513oBi2LqL/") == nil, "shared post isn't an event")
check(Store.facebookShareLink("https://www.facebook.com/groups/123") == nil, "group isn't an event")

// Calendar notes describe the plan without quoting the chat.
let ruleNote = PlanSummary(title: "Sunday ride", when: "Sunday 8 November, 8:30 am", start: nil, hasTime: true, place: "Shell Coldstream",
                           who: ["Alex", "Jordan"], undecided: nil, summary: "Alex wrote: “Sunday ride 8:30 at Shell Coldstream?”",
                           isPlan: true, byAI: false).calendarNote
check(ruleNote == "Ride plan: Sunday ride, Sunday 8 November, 8:30 am. Meeting at Shell Coldstream. Going: Alex, Jordan.", "rule-based plan described (\(ruleNote))")
check(!ruleNote.contains("wrote") && !ruleNote.contains("“"), "no chat message quoted in calendar notes")
let aiNote = PlanSummary(title: "x", when: "y", start: nil, hasTime: false, place: nil, who: [], undecided: nil,
                         summary: "A group ride to Marysville on Sunday morning.", isPlan: true, byAI: true).calendarNote
check(aiNote == "A group ride to Marysville on Sunday morning.", "Apple Intelligence summary used as it is")

let fbCal = FeedLinks.facebookCalendar("webcal://www.facebook.com/events/ical/upcoming/?uid=100000000000001&key=EXAMPLEKEY")
check(fbCal?.id == FeedLinks.facebookCalendarID && fbCal?.url.hasPrefix("https://www.facebook.com/events/ical/upcoming/") == true && fbCal?.type == .calendar, "Facebook's events calendar link becomes a calendar source")
check(FeedLinks.normalise("https://www.facebook.com/events/ical/upcoming/?uid=1&key=K")?.id == FeedLinks.facebookCalendarID, "pasting it anywhere works")
check(FeedLinks.facebookCalendar("https://www.facebook.com/events/1234567890/") == nil && FeedLinks.normalise("https://www.facebook.com/groups/example") == nil, "event and group links aren't calendars")
check(fbCal.map { SourceReader.wanted($0, "Torque & Terror bike night") && !SourceReader.wanted($0, "Sam's 30th birthday drinks") } == true, "only bike events come in from Facebook")
check(fbCal?.app == "Facebook", "listed under Facebook on the Sources page")
do {
    let st = Store(file: FileManager.default.temporaryDirectory.appendingPathComponent("rollcall-far-\(UUID().uuidString).json"))
    st.state.settings.radiusKm = 50
    let far = RideEvent(id: "facebook:1", title: "Geelong bike night", start: Date().addingTimeInterval(86400), end: nil, allDay: false,
                        location: "Example Waterfront", notes: "", url: nil, source: FeedLinks.facebookCalendarID,
                        sourceName: "Your Facebook events", distanceKm: 62, lastSeen: Date())
    var club = far; club.id = "club:1"; club.source = "ics-abc"
    st.state.events = [far.id: far, club.id: club]
    let ids = st.upcoming().map(\.id)
    check(ids == ["facebook:1"], "Facebook events you responded to show however far away; other far rides stay hidden")
}
do {
    // Made-up chat lines: a dismissed conversation keeps its summary but not people's messages.
    let st = Store(file: FileManager.default.temporaryDirectory.appendingPathComponent("rc-privacy-\(UUID().uuidString).json"))
    let lines = [ChatLine(id: "1", sender: "Sam", sent: Date(), text: "ride sat 9am?", mentionsWhen: true)]
    for (id, status) in [("a", PlanReview.Status.dismissed), ("b", .open)] {
        st.state.reviews[id] = PlanReview(id: id, feedID: "beeper-x", chatID: "x", lines: lines, summary: PlanFinder.guess(lines, now: Date()),
                                          status: status, created: Date(), updated: Date(), rideID: nil)
    }
    st.prune(refreshedSources: [], refreshStarted: Date())
    check(st.state.reviews["a"]?.lines.isEmpty == true && st.state.reviews["b"]?.lines.count == 1,
          "conversations RollCall dismissed itself don't keep people's messages")
    // Ones you dismissed wait under Reviewed for as long as Settings says.
    for (id, daysAgo) in [("c", 2.0), ("d", 9.0)] {
        st.state.reviews[id] = PlanReview(id: id, feedID: "beeper-x", chatID: id, lines: lines, summary: PlanFinder.guess(lines, now: Date()),
                                          status: .dismissed, created: Date(), updated: Date(), rideID: nil,
                                          dismissed: Date().addingTimeInterval(-daysAgo * 86400))
    }
    st.prune(refreshedSources: [], refreshStarted: Date())
    check(st.reviewedPlans().map(\.id) == ["c"] && st.state.reviews["d"]?.lines.isEmpty == true,
          "a plan you dismissed keeps its messages for a week, then they're deleted")
    st.state.settings.keepDismissedDays = 0
    st.forgetDismissedMessages()
    check(st.reviewedPlans().isEmpty && st.state.reviews["c"]?.lines.isEmpty == true, "Don't keep deletes them straight away")
}
do {
    let st = Store(file: FileManager.default.temporaryDirectory.appendingPathComponent("rc-home-\(UUID().uuidString).json"))
    st.state.settings.homeName = "12 Example St, Sunshine"; st.state.settings.homeCity = "Sunshine"
    st.state.settings.homeLatitude = -37.788123; st.state.settings.homeLongitude = 144.832987
    st.minimiseHome()
    check(st.state.settings.homeName == "Sunshine" && st.state.settings.homeLatitude == -37.79 && st.state.settings.homeLongitude == 144.83,
          "home keeps only the suburb and a rough spot")
}
do {
    // Made-up ride descriptions.
    let shared = "Big run this week!\nGOOGLE MAPS ROUTE: https://www.google.com/maps/dir/1+Example+St,+Sunshine/Some+Lookout/@-37.8,145.0,12z/data=!3m1\nMEET POINT: 1 Example St, Sunshine"
    check(Route.link(in: shared) == "https://www.google.com/maps/dir/1+Example+St,+Sunshine/Some+Lookout/@-37.8,145.0,12z/data=!3m1",
          "a route in the description is used as is")
    check(Route.link(in: "Pin for the cafe: https://maps.app.goo.gl/abc123") == nil, "a short map link on its own is a place, not a route")
    check(Route.link(in: "Route: https://maps.app.goo.gl/abc123.") == "https://maps.app.goo.gl/abc123", "a short link labelled as the route counts")
    let notes = "🏍 Meet point: 7:30am at Example Servo, Sunshine\n• Stop 1: Pretend Bakery, Hilltown\nCoffee stop - Make Believe Cafe → Lookout Rd, Fernvale\nDestination: Imaginary Falls\nEnd: 3pm"
    check(Route.stops(in: notes) == Route.Stops(meet: "Example Servo, Sunshine",
                                                via: ["Pretend Bakery, Hilltown", "Make Believe Cafe", "Lookout Rd, Fernvale"],
                                                destination: "Imaginary Falls"),
          "meeting place, stops and destination are read from labelled lines")
    check(Route.places(meetingPlace: "Example Servo", notes: "Bring snacks") == ["Example Servo"], "with nothing labelled, it's just the meeting place")
    let g = Route.googleMaps(from: "Sunshine", through: ["Example Servo", "Pretend Bakery", "Imaginary Falls"]) ?? ""
    check(g.hasPrefix("https://www.google.com/maps/dir/?api=1&origin=Sunshine&destination=Imaginary%20Falls&waypoints=Example%20Servo%7CPretend%20Bakery"),
          "Google Maps link goes from home through the stops")
    check(Route.waze(to: "Example Servo") == "https://waze.com/ul?q=Example%20Servo&navigate=yes", "Waze link")
    check(Route.appleMaps(from: "Sunshine", to: "Example Servo") == "maps://?saddr=Sunshine&daddr=Example%20Servo&dirflg=d", "Apple Maps link")
}

// Ride summaries
do {
    let long = """
    ROUTE MAP: https://www.google.com/maps/dir/1+Example+St/Some+Lookout/@-37.8,145.0,12z/data=!3m1!4m2!1m0!1m0!3e0?entry=ttu&g_ep=abcdefghijklmnop
    MEET POINT: 1 Example St, Sunshine VIC 3020
    STANDS UP: @ 7PM (we will NOT be waiting around after this time)
    DINNER: 12 Pretend Rd, Hilltown VIC 3999
    AFTER RIDE:
    CHILL SPOT: NO AFTER RIDE THIS TIME
    OUR SOCIALS BELOW:
    FACEBOOK: https://www.facebook.com/groups/example
    BY JOINING THIS EVENT YOU ACKNOWLEDGE THE FOLLOWING:
    Ride safe. Times: approximate.
    """
    check(Brief.items(in: long) == [
        Brief.Item(label: "Meet", value: "1 Example St, Sunshine VIC 3020"),
        Brief.Item(label: "Leave", value: "7pm (we will NOT be waiting around after this time)"),
        Brief.Item(label: "Dinner", value: "12 Pretend Rd, Hilltown VIC 3999"),
        Brief.Item(label: "Chill spot", value: "No after ride this time"),
    ], "labelled lines become a short summary, without links, socials, fine print or sentences")
    check(Brief.needsSummary(long), "a description with a huge link gets a summary")
    check(!Brief.needsSummary("Coffee and a short loop. Back by noon."), "a short description is shown as it is")
    check(Brief.items(in: long, location: "1 Example St, Sunshine VIC 3020, Australia").map(\.label) == ["Leave", "Dinner", "Chill spot"],
          "a meeting point that's the ride's place isn't shown twice")
    check(Brief.items(in: "Date: Sat 7 Nov\nTime: 9am\nDinner: The Pub").map(\.label) == ["Dinner"], "the date and time aren't shown twice")
    check(Brief.items(in: "Note: bring a jacket") == [], "one colon in a sentence isn't a summary")
    check(Brief.plainValue("MEET AT THE SERVO, 8 AM SHARP") == "Meet at the servo, 8am sharp", "capitals calmed down, times tidied")
    check(Brief.opening(String(repeating: "Lovely ride through the hills. ", count: 20), limit: 40) == "Lovely ride through the hills. Lovely…", "long text is cut at a word")
}
// Cross-posts
do {
    func ride(_ id: String, _ title: String, _ hour: Int, _ place: String = "", source: String = "feed") -> RideEvent {
        RideEvent(id: id, title: title, start: cal.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: hour))!,
                  end: nil, allDay: false, location: place, notes: "", url: nil, source: source,
                  sourceName: source, lastSeen: now)
    }
    let fb = ride("fb", "NOVEMBER '26 - PRETENDVILLE BIKE NIGHT", 16, "Pretendville Waterfront")
    let forum = ride("forum", "Pretendville Bike Night", 16, "Waterfront, Pretendville")
    let other = ride("other", "Pretendville Coffee Run", 16, "Pretendville Waterfront")
    let later = ride("later", "Pretendville Bike Night", 20)
    check(CrossPost.sameRide(fb, forum), "the same event on Facebook and a forum is one ride")
    check(!CrossPost.sameRide(fb, other), "a different ride from the same place isn't")
    check(!CrossPost.sameRide(fb, later), "the same name four hours later isn't")
    check(!CrossPost.sameRide(ride("a", "Sunday ride", 9), ride("b", "Sunday ride", 10)), "a vague name a hour apart isn't enough")
    check(CrossPost.sameRide(ride("a", "Brekky at Make Believe Cafe", 9, "Make Believe Cafe, Fernvale"),
                             ride("b", "Sunday social", 9, "Make Believe Cafe Fernvale")) == false,
          "same place and time with nothing else in common stays apart")

    let store = Store(file: FileManager.default.temporaryDirectory.appendingPathComponent("rc-crosspost-\(UUID()).json"))
    for e in [fb, forum, other] { store.state.events[e.id] = e }
    store.state.decisions["forum"] = .attending
    let shown = store.oneEach(store.state.events.values).map(\.id).sorted()
    check(shown == ["forum", "other"], "cross-posts show once, as the copy you decided on")
    check(store.copies(of: store.state.events["forum"]!).map(\.id) == ["fb"], "the other copies are listed")

    let msg = "Camping trip this weekend! Leaving Saturday 8am from the Example Servo in Sunshine, bring a tent and snacks"
    func plan(_ id: String, chat: String, _ text: String) -> PlanReview {
        let line = ChatLine(id: id, sender: "Sam", sent: now, text: text, mentionsWhen: true)
        return PlanReview(id: id, feedID: chat, chatID: chat, lines: [line],
                          summary: PlanSummary(title: "Camping trip", when: "Saturday", start: nil, hasTime: true, place: nil, who: [],
                                               undecided: nil, summary: "", isPlan: true, byAI: false),
                          status: .open, created: now, updated: now, rideID: nil)
    }
    check(CrossPost.samePlan(plan("1", chat: "a", msg), plan("2", chat: "b", msg + " 🏕️")), "one message sent to two chats is one plan")
    check(!CrossPost.samePlan(plan("1", chat: "a", msg), plan("2", chat: "a", msg)), "two plans in one chat stay apart")
    check(!CrossPost.samePlan(plan("1", chat: "a", msg), plan("2", chat: "b", "Anyone keen for a ride Saturday 8am from Sunshine?")),
          "a different message about the same day isn't the same plan")
}
// Ride details from the on-device model
do {
    let reply = """
    TITLE: CAMPING TRIP TO PRETEND FALLS
    START: 2026-11-07 08:00
    END: 2026-11-07 17:30
    MEET: Example Servo, Sunshine
    DESTINATION: Pretend Falls campground
    STOPS: Make Believe Bakery; Lookout Rd
    LINK: unknown
    **DETAILS:** Overnight camping ride. Bring a tent and food.
    """
    let d = RideDetails.parse(reply, now: now)
    check(d?.title == "Camping trip to pretend falls", "a shouted title is calmed down")
    check(d?.hasTime == true && d.map { comps($0.start!).hour } == 8, "start time read")
    check(d?.hours == 9.5, "length from the end time, to the half hour")
    check(d?.meet == "Example Servo, Sunshine" && d?.stops == ["Make Believe Bakery", "Lookout Rd"], "meeting place and stops read")
    check(d?.link == nil, "no link when it says unknown")
    check(d?.notes == "Overnight camping ride. Bring a tent and food.\nStops: Make Believe Bakery; Lookout Rd\nDestination: Pretend Falls campground",
          "notes carry the details, stops and destination on lines Route reads")
    check(Route.places(meetingPlace: d?.meet ?? "", notes: d?.notes ?? "") == ["Example Servo, Sunshine", "Make Believe Bakery", "Lookout Rd", "Pretend Falls campground"],
          "Route follows the filled-in stops")
    let vague = RideDetails.parse("TITLE: Night ride\nSTART: 2030-01-01\nMEET: the west\nLINK: www.example.com", now: now)
    check(vague?.start == nil && vague?.meet == nil && vague?.link == nil, "far-off dates, vague areas and half links are left out")
    check(RideDetails.routeTitle(from: "Yarra Glen", to: "Sugarloaf Reservoir, Christmas Hills VIC 3775") == "Yarra Glen to Sugarloaf Reservoir",
          "a chat ride is named after where it starts and ends")
    check(RideDetails.routeTitle(from: "12 Example St, Sunshine VIC 3020", to: nil) == "Ride from Sunshine", "a street address gives its suburb")
    check(RideDetails.routeTitle(from: nil, to: "Pretend Falls") == "Ride to Pretend Falls", "only the destination")
    check(Route.kurviger(through: [(-37.65, 145.37), (-37.531, 145.341)]) == "https://kurviger.de/?point=-37.65000,145.37000&point=-37.53100,145.34100",
          "Kurviger gets every point in order")
    check(Route.kurviger(through: [(-37.65, 145.37)]) == nil, "one point isn't a route")
    // The organiser's maps link is the route (made-up places and points).
    let g = "https://www.google.com/maps/dir/1+Example+St,+Sunshine+VIC/-37.9,145.2/Pretend+Pier,+Port+Example/@-37.8,145.0,16931m/data=!3m1!1e3!4m20!4m19!1m10!1m1!1s0x1:0x2!2m2!1d144.90!2d-37.83!3m4!1m2!1d145.07!2d-37.88!3s0x3:0x4!1m0!1m5!1m1!1s0x5:0x6!2m2!1d144.93!2d-37.84!3e0"
    check(Route.linkPlaces(g) == ["-37.83,144.90", "-37.88,145.07", "-37.9,145.2", "-37.84,144.93"],
          "a Google route's stops and dragged-through points, in order")
    check(!Route.linkAvoidsHighways(g), "a route that may use highways")
    // Shaped like a real organiser's link: a point dragged through on the way from a stop given only in the path,
    // and "Avoid highways" (made-up places and points).
    let h = "https://www.google.com/maps/dir/1+Example+St,+Sunshine+VIC/-37.86,144.88/Pretend+Hall/@-37.8,144.9,10075m/data=!3m1!1e3!4m22!4m21"
        + "!1m5!1m1!1s0x1:0x2!2m2!1d144.90!2d-37.82!1m5!3m4!1m2!1d144.91!2d-37.80!3s0x3:0x4!1m5!1m1!1s0x5:0x6!2m2!1d144.96!2d-37.80!2m1!1b1!3e0"
    check(Route.linkPlaces(h) == ["-37.82,144.90", "-37.86,144.88", "-37.80,144.91", "-37.80,144.96"],
          "a point dragged through after a stop that's only in the path is kept")
    check(Route.linkAvoidsHighways(h), "a Google route planned avoiding highways")
    check(Route.linkPlaces("https://www.google.com/maps/dir/Example+Servo/Pretend+Falls/") == ["Example Servo", "Pretend Falls"], "stops named in the path")
    check(Route.linkPlaces("https://www.google.com/maps/dir/?api=1&origin=A+Town&destination=C+Town&waypoints=B+Town%7CD+Town") == ["A Town", "B Town", "D Town", "C Town"],
          "a Google route link made by an app")
    check(Route.linkPlaces("https://maps.apple.com/?saddr=A+Town&daddr=C+Town") == ["A Town", "C Town"], "an Apple Maps route")
    check(Route.point("-37.9,145.2")! == (-37.9, 145.2) && Route.point("Pretend Falls") == nil, "map points are read as points")
    // Working out a route from a ride's title and description (made-up rides).
    check(Route.guess(title: "Sunday cruise", location: "Example Servo, Sunshine", notes: "Coffee then heading to Pretend Falls for lunch.")
          == ["Example Servo, Sunshine", "Pretend Falls"], "a destination from \"heading to …\"")
    check(Route.guess(title: "Hills loop", location: "Make Believe Bakery", notes: "Easy pace, lunch at Lake Imaginary before home.")
          == ["Make Believe Bakery", "Lake Imaginary"], "a destination from \"lunch at …\"")
    check(Route.guess(title: "Yarra Glen to Sugarloaf Reservoir", location: "", notes: "") == ["Yarra Glen", "Sugarloaf Reservoir"],
          "a title like \"A to B\" gives both ends")
    check(Route.guess(title: "Ride to Pretend Falls", location: "Example Servo", notes: "") == ["Example Servo", "Pretend Falls"],
          "\"Ride to B\" keeps the meeting place as the start")
    check(Route.guess(title: "Bike night", location: "Example Waterfront", notes: "Heading to Saturday's show after.") == ["Example Waterfront"],
          "a day isn't a place")
    check(Route.guess(title: "Back to the 80s night", location: "Example Hall", notes: "") == ["Example Hall"], "a title that isn't a route")
    do {
        let st = Store(file: FileManager.default.temporaryDirectory.appendingPathComponent("rc-route-\(UUID().uuidString).json"))
        let ride = RideEvent(id: "r1", title: "Sunday cruise", start: Date(), end: nil, allDay: false, location: "Example Servo",
                             notes: "Nice and easy.", url: nil, source: "manual", sourceName: "Added by you", lastSeen: Date())
        st.state.foundRoutes["r1"] = FoundRoute(places: ["Example Servo", "Pretend Falls"], from: Route.fingerprint(ride))
        check(st.routePlaces(ride) == ["Example Servo", "Pretend Falls"], "a found route is used for the map")
        var changed = ride; changed.notes = "Now going somewhere else."
        st.state.settings.homeName = "Sunshine"; st.state.settings.homeCity = "Sunshine"
        check(st.routePlaces(changed) == ["Sunshine", "Example Servo"],
              "a found route is worked out again when the details change; meanwhile a one-place ride starts from your suburb")
        var nowhere = ride; nowhere.location = ""; nowhere.notes = ""
        check(st.routePlaces(nowhere).isEmpty, "a ride with no place has no route")
        var written = ride; written.notes = "Destination: Lake Imaginary"
        check(st.routePlaces(written) == ["Example Servo", "Lake Imaginary"], "places written in the details win")
    }
    check(RideDetails.routeTitle(from: nil, to: nil) == nil, "no places, no route name")
    check(RideDetails.parse("Sorry, I can't help with that.", now: now) == nil, "a reply in the wrong shape is ignored")
    check(AppleModel.tidied("Shit yeah, ride Sunday you legends") == "… yeah, ride Sunday you legends", "swearing is left out of what the model reads")
    check(AppleModel.tidied("Meet at Shitake Cafe? Scunthorpe") == "Meet at … Cafe? Scunthorpe", "words that only start like one may be hidden too, which only affects what the model reads")
}
// Preparing text for Apple's on-device model
do {
    let raw = "Sooooooo keen!!!!!!!! hahahahahaha\u{200B} see https://www.facebook.com/events/123/?fbclid=AbCdEf&ref=x   ok"
    check(AppleModel.prepared(raw) == "Sooo keen!!! hahaha see https://www.facebook.com/events/123/ ok",
          "runs, invisible characters, tracking and extra spaces are cut down")
    check(AppleModel.originalLink("https://www.facebook.com/events/123/", in: raw) == "https://www.facebook.com/events/123/?fbclid=AbCdEf&ref=x",
          "a shortened link comes back as it was written")
    check(AppleModel.originalLink("https://example.com/made-up", in: raw) == nil, "a link the text never had is dropped")

    let lines = (1...40).map { "[Sat 9:0\($0 % 10) am] Sam: message number \($0) " + String(repeating: "blah ", count: 30) }
    let input = AppleModel.Input(heading: "Chat: Sunday Crew", lines: lines, keep: [2, 39])
    let fitted = AppleModel.fitted(input, maxChars: 1000)
    check(fitted.count <= 1000, "trimmed to fit")
    check(fitted.contains("message number 3 ") && fitted.contains("message number 40 "), "the key messages stay")
    check(!fitted.contains("message number 1 "), "the oldest other messages go first")
    let post = AppleModel.fitted(AppleModel.Input(heading: "Event post", lines: [String(repeating: "Ride details. ", count: 1000)]), maxChars: 500)
    check(post.count <= 500 && post.hasSuffix("…"), "one long post is cut short")

    check(AppleModel.keyOnly(input)?.lines == [lines[2], lines[39]], "a second try has just the key messages")
    check(AppleModel.keyOnly(AppleModel.Input(heading: "", lines: ["a", "b"], keep: [0, 1])) == nil, "no second try when nothing would change")
    let mixed = AppleModel.Input(heading: "Chat", lines: ["Ride Sunday 9am?", "ਸਵਾਰੀ ਐਤਵਾਰ ਨੂੰ", "Count me in"], keep: [0])
    check(AppleModel.readableOnly(mixed)?.lines == ["Ride Sunday 9am?", "Count me in"], "messages in a script it can't read are left out")
    check(AppleModel.looksLikeRefusal("Sorry, I can't help with that.") && AppleModel.looksLikeRefusal("I'm sorry, but I cannot"),
          "a refusal in words is spotted")
    check(!AppleModel.looksLikeRefusal("PLAN: yes\nTITLE: Sorry state of the roads ride"), "a normal reply isn't")
}
// Editing a ride
do {
    let store = Store(file: FileManager.default.temporaryDirectory.appendingPathComponent("rc-edit-\(UUID()).json"))
    let start = cal.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 0))!
    let item = ICSEvent(uid: "show", title: "bike ride to the pretend show", start: start, end: start.addingTimeInterval(3 * 3600),
                        allDay: false, location: "Pretendville", notes: "", url: nil)
    store.merge([item], source: "feed", sourceName: "Feed")
    let id = Store.eventID(source: "feed", item: item)
    let fixed = start.addingTimeInterval(9 * 3600)
    store.state.rideEdits[id] = RideEdit(title: "Pretend Show ride", start: fixed, end: fixed.addingTimeInterval(5 * 3600), allDay: false,
                                         location: "Example Servo, Sunshine", notes: "Bring cash", url: nil)
    store.merge([item], source: "feed", sourceName: "Feed")
    let e = store.state.events[id]
    check(e?.title == "Pretend Show ride" && e?.start == fixed && e?.location == "Example Servo, Sunshine" && e?.notes == "Bring cash",
          "your changes stay when the source is checked again")
    check(e?.latitude == nil, "a changed place is looked up again")
}

// A removed ride stays removed when its source is checked again, until a week after it.
do {
    let store = Store(file: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("removed-\(UUID()).json"))
    let start = Date().addingTimeInterval(3 * 86400)
    let item = ICSEvent(uid: "r1", title: "Pretend Sunday ride", start: start, end: nil, allDay: false,
                        location: "", notes: "", url: nil, latitude: nil, longitude: nil)
    let id = Store.eventID(source: "feed", item: item)
    store.state.removedRides[id] = start
    store.merge([item], source: "feed", sourceName: "Feed")
    check(store.state.events[id] == nil, "a removed ride doesn't come back")
    store.state.removedRides[id] = Date().addingTimeInterval(-8 * 86400)
    store.prune(refreshedSources: [], refreshStarted: Date())
    check(store.state.removedRides.isEmpty, "removed rides are forgotten a week after")
}
// An all-day ride lasts to the end of its day, whatever end the source gives.
do {
    let day = Calendar.current.startOfDay(for: Date())
    func allDay(_ end: Date?) -> RideEvent {
        RideEvent(id: "a", title: "Pretend shindig", start: day, end: end, allDay: true, location: "", notes: "", url: nil,
                  source: "feed", sourceName: "Feed", lastSeen: Date())
    }
    let midnight = Calendar.current.date(byAdding: .day, value: 1, to: day)!
    check(allDay(nil).finish == midnight && allDay(day).finish == midnight, "an all-day ride with no end, or end = start, lasts all day")
    let twoDays = Calendar.current.date(byAdding: .day, value: 2, to: day)!
    check(allDay(twoDays).finish == twoDays, "a two-day ride lasts both days")
    let store = Store(file: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("allday-\(UUID()).json"))
    store.state.events["a"] = allDay(day)
    check(store.upcoming(now: day.addingTimeInterval(12 * 3600)).count == 1, "an all-day ride still shows at midday on the day")
}

// Your Facebook replies: Going and Interested carry over, unless you've chosen yourself in RollCall.
do {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("rollcall-replies-\(UUID().uuidString).json")
    let s = Store(file: file)
    func event(_ n: Int, _ partstat: String?) -> String {
        "BEGIN:VEVENT\r\nDTSTART:20261120T223000Z\r\nUID:e10000000\(n)@facebook.com\r\nSUMMARY:Made-up ride \(n)\r\n"
            + "URL:https://www.facebook.com/events/10000000\(n)/\r\n" + (partstat.map { "PARTSTAT:\($0)\r\n" } ?? "") + "END:VEVENT\r\n"
    }
    func calendar(_ replies: [String?]) -> [ICSEvent] {
        ICSParser.parse("BEGIN:VCALENDAR\r\n" + replies.enumerated().map { event($0.offset, $0.element) }.joined() + "END:VCALENDAR\r\n", now: now)
    }
    let first = calendar(["ACCEPTED", "TENTATIVE", nil, "ACCEPTED"])
    check(first.map(\.response) == [.attending, .maybe, nil, .attending], "Facebook's Going and Interested are read from the calendar")
    let src = FeedLinks.facebookCalendarID
    s.merge(first, source: src, sourceName: "Your Facebook events", now: now)
    let id = { (n: Int) in Store.eventID(source: src, item: first[n]) }
    s.state.decisions[id(3)] = .skip   // you skipped this one in RollCall before the calendar was read
    let changed = s.carryResponses(first, source: src)
    check(Set(changed) == [id(0), id(1)], "replies carry over to undecided rides")
    check(s.decision(id(0)) == .attending && s.decision(id(1)) == .maybe && s.decision(id(2)) == .undecided,
          "Going becomes Going and Interested becomes Maybe")
    check(s.decision(id(3)) == .skip, "your own choice in RollCall isn't undone")
    // Interested becomes Going on Facebook; you choose Skip in RollCall for ride 0.
    s.state.decisions[id(0)] = .skip
    let second = calendar(["TENTATIVE", "ACCEPTED", nil, "ACCEPTED"])
    check(s.carryResponses(second, source: src) == [id(1)], "a changed reply on Facebook carries over")
    check(s.decision(id(1)) == .attending, "Interested to Going on Facebook becomes Going here")
    check(s.decision(id(0)) == .skip, "a ride you changed yourself keeps your choice")
}

// Weather along the route: a made-up straight route of about 100 km due north, ridden in 2 hours.
do {
    let line = (0...100).map { CLLocationCoordinate2D(latitude: -38.0 + Double($0) * 0.009, longitude: 145.0) }
    let leave = now
    let pts = RouteWeather.points(along: [Array(line[0...40]), Array(line[40...])], seconds: 7200, leave: leave)
    check(pts.count == 3, "a 100 km route gets a point at the start, middle and finish (got \(pts.count))")
    check(abs(pts[1].km - pts[2].km / 2) < 0.01 && abs(pts[2].km - 100) < 1, "points are evenly spaced along the road")
    check(abs(pts[1].time.timeIntervalSince(leave) - 3600) < 1 && abs(pts[2].time.timeIntervalSince(leave) - 7200) < 1,
          "each point has when you'd reach it")
    check(abs(pts[1].spot.latitude - (-37.55)) < 0.01, "the middle point is half way up the road")
    let short = RouteWeather.points(along: [Array(line[0...10])], seconds: 900, leave: leave)
    check(short.count == 2, "a short route gets the start and finish")
    let long = RouteWeather.points(along: [line + line.map { CLLocationCoordinate2D(latitude: $0.latitude + 0.91, longitude: 145.0) }
        + line.map { CLLocationCoordinate2D(latitude: $0.latitude + 1.82, longitude: 145.0) } + line.map { CLLocationCoordinate2D(latitude: $0.latitude + 2.73, longitude: 145.0) }
        + line.map { CLLocationCoordinate2D(latitude: $0.latitude + 3.64, longitude: 145.0) }], seconds: 30000, leave: leave)
    check(long.count == RouteWeather.maxPoints, "a very long route is capped at \(RouteWeather.maxPoints) points")
    let url = RouteWeather.url(for: pts)?.absoluteString ?? ""
    check(url.contains("latitude=-38.000,-37.550") && url.contains("timeformat=unixtime"), "one forecast request for all the points")

    // A saved sample reply for two points (Open-Meteo's layout, made-up values).
    let t0 = leave.timeIntervalSince1970.rounded(.down)
    func hourly(_ temp: Double, _ rain: Double?, _ gust: Double) -> String {
        """
        {"hourly":{"time":[\(t0 - 3600),\(t0),\(t0 + 3600),\(t0 + 7200)],"temperature_2m":[10,\(temp),\(temp + 1),\(temp + 2)],
        "precipitation_probability":[0,\(rain.map { "\($0)" } ?? "null"),70,80],"wind_speed_10m":[5,12,14,16],
        "wind_gusts_10m":[9,\(gust),\(gust),\(gust)],"weather_code":[0,3,61,61]}}
        """
    }
    let two = [pts[0], pts[2]]
    let read = RouteWeather.read(Data("[\(hourly(18, 10, 30)),\(hourly(14, 20, 55))]".utf8), for: two)
    check(read.count == 2, "a reply for two points gives two forecasts")
    check(read.first?.temperature == 18 && read.first?.rainChance == 10 && read.first?.code == 3,
          "the start's forecast is for the hour you leave")
    check(read.last?.temperature == 16 && read.last?.rainChance == 80 && read.last?.gusts == 55,
          "the finish's forecast is for two hours later")
    check(RouteWeather.read(Data(hourly(18, nil, 30).utf8), for: [pts[0]]).isEmpty, "an hour without a forecast is left out")
    check(RouteWeather.read(Data(hourly(18, 10, 30).utf8), for: [pts[0]]).count == 1, "a reply for one point is read too")
    let farOff = RouteWeather.Point(spot: pts[0].spot, km: 0, time: leave.addingTimeInterval(86400))
    check(RouteWeather.read(Data(hourly(18, 10, 30).utf8), for: [farOff]).isEmpty, "a time outside the reply is left out")

    check(RouteWeather.readyDate(leave: now.addingTimeInterval(3 * 86400), now: now) == nil, "a ride this week has its forecast")
    let ready = RouteWeather.readyDate(leave: now.addingTimeInterval(10 * 86400), now: now)
    check(ready == Calendar.current.date(byAdding: .day, value: 3, to: Calendar.current.startOfDay(for: now)),
          "a ride 10 days out says its forecast is ready in 3 days")
    check(RouteWeather.describe(0).word == "Clear" && RouteWeather.describe(63).word == "Rain" && RouteWeather.describe(95).word == "Storms",
          "weather codes have words")
}


// Road alerts: made-up alerts near a made-up route heading east from (-37.80, 144.90) to (-37.80, 145.00).
do {
    let route = (0...10).map { CLLocationCoordinate2D(latitude: -37.80, longitude: 144.90 + Double($0) * 0.01) }
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let rideFrom = now.addingTimeInterval(3 * 3600), rideTo = now.addingTimeInterval(6 * 3600)
    func iso(_ d: Date) -> String { ISO8601DateFormatter().string(from: d) }
    let unplanned = """
    {"meta": {"total_records": 3, "total_pages": 2, "page": 1, "limit": 500, "count": 3},
     "data": {"type": "FeatureCollection", "features": [
      {"type": "Feature", "geometry": {"type": "Point", "coordinates": [144.951, -37.8003]},
       "properties": {"id": "1", "status": "Active", "eventLocationStatus": "Active", "eventType": "Crash",
        "eventSubType": "Vehicle Collision", "closedRoadName": "Example Road", "description": "Made-up crash",
        "created": "\(iso(now))", "endTime": "\(iso(now.addingTimeInterval(7200)))",
        "impact": {"direction": "Both directions", "impactType": "Road closed"},
        "reference": {"startIntersectionLocality": "SAMPLEVILLE"}}},
      {"type": "Feature", "geometry": {"type": "LineString", "coordinates": [[145.30, -37.60], [145.31, -37.61]]},
       "properties": {"id": "2", "status": "Active", "eventType": "Hazard", "impact": {"impactType": "Lanes closed"}}},
      {"type": "Feature", "geometry": {"type": "Point", "coordinates": [144.95, -37.80]},
       "properties": {"id": "3", "status": "Inactive", "eventType": "Hazard"}}
     ]}, "links": []}
    """
    let u = RoadAlerts.readUnplanned(Data(unplanned.utf8))
    check(u?.pages == 2 && u?.alerts.count == 2, "unplanned alerts are read and finished ones left out")
    let crash = u?.alerts.first
    check(crash?.road == "Example Road" && crash?.place == "Sampleville" && crash?.closesRoad == true && crash?.planned == false
          && crash?.spots.first?.latitude == -37.8003, "an alert's road, place, closure and spot are read")

    let planned = """
    {"type": "FeatureCollection", "nextPageDetails": {"nextPageToken": "abc", "hasMoreRecords": true}, "features": [
      {"type": "Feature", "geometry": {"type": "GeometryCollection", "geometries": [
         {"type": "LineString", "coordinates": [[144.92, -37.799], [144.93, -37.799]]}]},
       "properties": {"id": "p1", "status": "Active", "eventType": "Roadworks", "closedRoadName": "Sample Street",
        "duration": {"start": "\(iso(now.addingTimeInterval(86400)))", "end": "\(iso(now.addingTimeInterval(2 * 86400)))"},
        "impact": {"impactType": "Lanes closed"}}},
      {"type": "Feature", "geometry": {"type": "GeometryCollection", "geometries": [{"type": "Point", "coordinates": [144.97, -37.8002]}]},
       "properties": {"id": "p2", "status": "Active", "eventType": "Roadworks",
        "duration": {"start": "\(iso(now))", "end": "\(iso(now.addingTimeInterval(86400)))"}}}
    ]}
    """
    let p = RoadAlerts.readPlanned(Data(planned.utf8))
    check(p?.next == "abc" && p?.alerts.count == 2 && p?.alerts.first?.spots.count == 2, "booked works and the next page are read")
    let kept = (try? JSONEncoder().encode(p?.alerts ?? [])).flatMap { try? JSONDecoder().decode([RoadAlerts.Alert].self, from: $0) }
    check(kept?.map(\.id) == p?.alerts.map(\.id) && kept?.first?.spots.first?.latitude == p?.alerts.first?.spots.first?.latitude
          && kept?.first?.spots.first?.longitude == p?.alerts.first?.spots.first?.longitude, "booked works saved to disk read back the same")

    let all = (u?.alerts ?? []) + (p?.alerts ?? [])
    let found = RoadAlerts.on(route, from: rideFrom, to: rideTo, alerts: all, now: now).map(\.id)
    check(found.contains("1"), "a closure on the route shows")
    let marked = RoadAlerts.on(route, from: rideFrom, to: rideTo, alerts: all, now: now).first { $0.id == "1" }?.mark
    check(marked.map { abs($0.latitude + 37.8003) < 0.0001 && abs($0.longitude - 144.951) < 0.0001 } == true,
          "a matched alert knows where it is on the route, for the map")
    check(!found.contains("2"), "an alert in another suburb doesn't")
    check(found.contains("p2") && !found.contains("p1"), "booked works show only if they overlap the ride")
    let nextWeek = RoadAlerts.on(route, from: rideFrom.addingTimeInterval(7 * 86400), to: rideTo.addingTimeInterval(7 * 86400), alerts: all, now: now)
    check(nextWeek.isEmpty, "alerts happening now don't show on a ride next week")
    func alert(_ spots: [(Double, Double)]) -> RoadAlerts.Alert {
        RoadAlerts.Alert(id: "x", planned: false, kind: "", impact: "", road: "", place: "", details: "", start: nil, end: nil,
                         spots: spots.map { CLLocationCoordinate2D(latitude: $0.0, longitude: $0.1) })
    }
    func shows(_ a: RoadAlerts.Alert) -> Bool { !RoadAlerts.on(route, from: rideFrom, to: rideTo, alerts: [a], now: now).isEmpty }
    check(!shows(alert([(-37.801, 144.95)])), "an alert on a side street 110 m off the route doesn't show")
    check(!shows(alert([(-37.79, 144.95), (-37.80, 144.95), (-37.81, 144.95)])), "a closure on a road the route only crosses doesn't show")
    check(shows(alert([(-37.80, 144.94), (-37.80, 144.945), (-37.80, 144.95)])), "a closure along the route shows")
    check(shows(alert([(-37.80, 144.99), (-37.80, 145.03)])), "a long straight closure the route rides the start of shows")
    check(RoadAlerts.readUnplanned(Data("not json".utf8)) == nil, "a broken reply isn't read")
    check(AlertSummary.trimmed("Road Program activities occurring between 02/09/2026 and 31/03/2027 during the following times: Weekdays 7:00 PM to 5:00 AM. Impact to traffic will be lanes closed southbound. Altered speed limit during operation will be 40 and the traffic delay is expected to be 0 to 5 min.")
          == "Road Program. lanes closed southbound. 40 km/h, delays 0 to 5 min.", "the model reads alerts without dates, times or set phrases")
    var blocked = alert([(-37.80, 144.95)]); blocked.impact = "Lanes blocked"; blocked.road = "Made Up Street"; blocked.place = "Testville"
    var other = blocked; other.id = "y"; other.road = "Another Road"
    check(AlertSummary.plain([blocked]) == "Lanes blocked on Made Up Street, Testville", "the plain label says what and where")
    check(AlertSummary.plain([blocked, other]) == "Lanes blocked on Made Up Street, Testville (and 1 more)", "the plain label counts the others")

    let roads = RoadAlerts.byRoad([
        RoadAlerts.Alert(id: "a", planned: true, kind: "Planned roadworks", impact: "Lanes blocked", road: "Sample Freeway", place: "Northtown", details: "", start: nil, end: nil, spots: []),
        RoadAlerts.Alert(id: "b", planned: true, kind: "Planned roadworks", impact: "Lanes blocked", road: "Sample Freeway", place: "Southtown", details: "", start: nil, end: nil, spots: []),
        RoadAlerts.Alert(id: "c", planned: true, kind: "Planned roadworks", impact: "Closures", road: "Example Street", place: "Northtown", details: "", start: nil, end: nil, spots: []),
        RoadAlerts.Alert(id: "d", planned: true, kind: "Planned roadworks", impact: "Closures", road: "Sample Freeway", place: "Northtown", details: "", start: nil, end: nil, spots: []),
        RoadAlerts.Alert(id: "e", planned: true, kind: "Planned roadworks", impact: "Lanes blocked", road: "Sample Out-Example Ramp Of", place: "Northtown", details: "", start: nil, end: nil, spots: []),
        RoadAlerts.Alert(id: "f", planned: true, kind: "Planned roadworks", impact: "Lanes blocked", road: "Example-Sample In Ramp On", place: "Southtown", details: "", start: nil, end: nil, spots: []),
    ])
    check(roads.count == 3 && roads[0].name == "Sample Freeway" && roads[0].places == ["Northtown", "Southtown"] && roads[0].closesRoad,
          "alerts are grouped by road, showing the worst, closures first")
    check(roads.last?.name == "On and off ramps" && roads.last?.alerts.count == 2, "ramps are shown together")

    // Feed times are Victorian, with no time zone; booked works can run at set weekly times.
    let vic = RoadAlerts.calendar
    func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {   // November 2026: the 9th is a Monday
        vic.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }
    check(RoadAlerts.date("2026-11-10T18:30:00") == at(10, 18, 30), "feed times are read as Victorian time")
    check(RoadAlerts.seconds("PT6H") == 21600 && RoadAlerts.seconds("P1DT2H30M") == 95400 && RoadAlerts.seconds("PT-14H-30M") == -52200
          && RoadAlerts.seconds("soon") == nil, "lengths like PT6H and PT-14H-30M are read")
    check(RoadAlerts.minutes("9:30 PM") == 1290 && RoadAlerts.minutes("12:00 AM") == 0 && RoadAlerts.minutes("12:15 PM") == 735
          && RoadAlerts.minutes("21:30") == 1290, "times of day like 9:30 PM are read")
    let weekdays = """
    {"type": "FeatureCollection", "features": [
      {"type": "Feature", "geometry": {"type": "GeometryCollection", "geometries": [{"type": "Point", "coordinates": [144.95, -37.80]}]},
       "properties": {"id": "w", "status": "Pending", "impactType": "x", "impact": {"impactType": "Closures"},
        "duration": {"start": "2026-11-01T00:00:00", "end": "2026-11-30T00:00:00", "recurrences": [
          {"startDay": "Monday", "daysDuration": 1, "startTime": "8:00 PM", "duration": "PT-15H0M", "allDay": false},
          {"startDay": "Saturday", "daysDuration": 1, "startTime": "00:00", "duration": "PT24H", "allDay": true}]}}},
      {"type": "Feature", "geometry": {"type": "Point", "coordinates": [144.95, -37.80]},
       "properties": {"id": "old", "status": "Pending", "duration": {"start": "2024-02-01T00:00:00", "end": "2025-06-30T00:00:00"}}}
    ]}
    """
    let w = RoadAlerts.readPlanned(Data(weekdays.utf8), now: at(8, 12))
    check(w?.alerts.count == 1 && w?.alerts.first?.closesRoad == true, "works already over are dropped, and Closures count as closed roads")
    if let works = w?.alerts.first {
        check(works.times.count == 2 && works.end == at(30, 0).addingTimeInterval(86400), "weekly times are read, and a midnight end lasts that day")
        check(RoadAlerts.isOn(works, from: at(9, 21), to: at(9, 23)), "Monday night works are on during a Monday night ride")
        check(RoadAlerts.isOn(works, from: at(10, 3), to: at(10, 4)), "overnight works are still on early Tuesday")
        check(!RoadAlerts.isOn(works, from: at(10, 10), to: at(10, 14)), "they're off during a Tuesday daytime ride")
        check(RoadAlerts.isOn(works, from: at(14, 15), to: at(14, 16)), "all-day Saturday works are on all Saturday")
        check(!RoadAlerts.isOn(works, from: at(30, 23).addingTimeInterval(7200), to: at(30, 23).addingTimeInterval(10000)), "they're off once the dates end")
    }
}

print(failures == 0 ? "\nAll tests passed" : "\n\(failures) failed")
exit(failures == 0 ? 0 : 1)
