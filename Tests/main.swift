import Foundation

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
store.merge(m, source: "meetup-x", sourceName: "X", groupURL: "https://www.meetup.com/x/", now: now)
let far = ICSEvent(uid: "far", title: "Far ride", start: now.addingTimeInterval(86400 * 3), end: nil, allDay: false,
                   location: "Mildura", notes: "", url: nil, latitude: -34.18, longitude: 142.16)
store.merge([far], source: "meetup-x", sourceName: "X", groupURL: nil, now: now)
let up = store.upcoming(now: now)
check(up.count == 1 && up[0].title == "Great Ocean Road day ride", "far ride (Mildura) hidden, Geelong shown")
check(abs((up.first?.distanceKm ?? 0) - 64) < 10, "Geelong about 64 km from CBD (\(Int(up.first?.distanceKm ?? 0)))")
let later = now.addingTimeInterval(3600)
store.merge(Array(m.prefix(0)), source: "meetup-x", sourceName: "X", groupURL: nil, now: later)
store.prune(refreshedSources: ["meetup-x"], refreshStarted: later, now: later)
check(store.state.events.isEmpty, "rides that vanished from their feed are dropped")
store.merge(m, source: "meetup-x", sourceName: "X", groupURL: nil, now: now)
store.state.decisions["meetup-x:event_316000001@meetup.com"] = .attending
store.prune(refreshedSources: ["meetup-x"], refreshStarted: later, now: later)
check(store.state.events.count == 1, "...unless you're attending")
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
              end: nil, allDay: false, location: "45 Hoddle Street, Richmond", notes: notes, url: nil, groupURL: nil,
              source: source, sourceName: "SUNDAY CREW", lastSeen: Date())
}
check(Crew.rideTag(ride("Halloween Pre-Meet Ride")) == "#RCHalloweenPreMeet31Oct", "ride tag from the name and date")
check(Crew.rideTag(ride("TTR RETURNS AFTER WEEKS")) == "#RCTTRReturns31Oct", "shouting names are tamed, short acronyms kept")
check(Crew.rideTag(ride("Sunday ride", "see you there #RCBlackSpur8Nov")) == "#RCBlackSpur8Nov", "a tag in someone's invite wins")
check(Crew.rideTag(ride("Sunday ride"), override: "MyTag") == "#MyTag", "a typed tag wins")
var crewT = Together(); crewT.tags = "hooligoon, #RollCall #melbriders"; crewT.discord = "https://discord.gg/abc"; crewT.intercomGroup = "DMC SUNDAY CREW"
let tagsOut = Crew.hashtags(ride("Halloween Pre-Meet Ride"), together: crewT, links: CrewLinks(tags: "#sundaycrew"), override: nil)
check(tagsOut == ["#RCHalloweenPreMeet31Oct", "#RollCall", "#sundaycrew", "#hooligoon", "#melbriders"], "tags: ride, app, group, yours, no repeats")
let inv = Crew.invite(ride("Halloween Pre-Meet Ride"), when: "Saturday 31 October, 5:30 pm", together: crewT, links: CrewLinks(discord: "https://discord.gg/group"), override: nil)
check(inv.contains("discord.gg/group") && !inv.contains("discord.gg/abc"), "a group's Discord replaces yours")
check(inv.contains("Cardo: DMC SUNDAY CREW") && inv.contains("Find My") && inv.contains("maps.apple.com/?q=45%20Hoddle"), "invite has intercom, location app and map")
check(Crew.ics(ride("Halloween, Pre-Meet"), description: inv).contains("SUMMARY:Halloween\\, Pre-Meet"), "calendar file escapes commas")
check(Crew.key(forSource: "file") == "yours" && Crew.key(forSource: "facebook") == "facebook", "hand-added rides share crew settings")
check(Updater.isNewer("1.10", than: "1.9") && Updater.isNewer("v1.1", than: "1.0") && !Updater.isNewer("1.0", than: "1.0.0"), "version comparison")
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
_ = chatStore.merge([farRide], source: chatFeed.id, sourceName: chatFeed.name, groupURL: nil, needsCheck: true, now: now)
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

print(failures == 0 ? "\nAll tests passed" : "\n\(failures) failed")
exit(failures == 0 ? 0 : 1)
