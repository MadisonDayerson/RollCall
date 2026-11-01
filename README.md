# RollCall

![RollCall logo](Design/RollCall.png)

A menu bar app for motorcycle group rides (it started as a Melbourne one, and was called MotoRides). It collects rides from Facebook events and
Instagram posts you add, WhatsApp and other chats (through Beeper), forums (NetRider), event websites
(Eventbrite, club sites), Meetup groups and club calendars. For each ride you pick Attending, Maybe
or Skip, and rides you're attending go into a **RollCall** calendar in Apple Calendar.

## What it can't do, and why

- **It can't search Facebook for you.** Facebook stopped letting apps search for events or groups,
  or read groups' events. Instead you add each Facebook event yourself (steps below).
- **It can't join groups or RSVP for you.** No app is allowed to press those buttons. RollCall
  opens the right page so you can press **Join** or **Going** yourself.
- **It can't read Instagram either.** Instagram (also owned by Meta) shut down the API that let apps
  read other accounts' posts. RollCall keeps a list of accounts to check (Hooligoon is on it) and
  opens them in your browser. When you see a ride, copy the caption and add it in two clicks.
- **It can't read WhatsApp directly.** WhatsApp has no way for apps to read personal or group
  chats, and unofficial tools can get your number banned. RollCall reads chats through
  **Beeper Desktop** instead, which has an official local API (steps below).
- **It doesn't scrape or auto-click Facebook or Instagram.** That breaks Facebook's rules and can get your
  account restricted.

## First-time setup

1. Open Terminal (press ⌘ Space, type **Terminal**, press Return).
2. Paste this and press Return:
   ```bash
   ~/Downloads/Personal/RollCall/build.sh --install
   ```
3. The **Set up RollCall** wizard opens. It goes through:
   - **Your area:** type a suburb or town and press **Find**, then pick how far to look.
   - **Chats:** RollCall reads group chats through the free **Beeper** app, because WhatsApp,
     Messenger and Messages don't let other apps read chats. The wizard links to the download, then
     shows the next step for wherever you're up to (switch on Beeper Desktop API, connect, tick chats).
   - **Groups & accounts:** suggestions for your area (Victorian groups if you're in Victoria, an
     Eventbrite search for your city elsewhere), plus a box to paste any link or @instagram name.
   - **Calendar:** allow calendar access, then choose where the **RollCall** calendar goes: iCloud
     (Apple Calendar), Google (after adding your Google account in **System Settings → Internet
     Accounts**; the wizard shows the steps), Exchange or this Mac.
   - **All set:** open at login, and allow notifications for chat plans.
4. Every step can be skipped. Menu → **Set up RollCall…** opens the wizard again.
5. The first time you add a Facebook event, macOS may ask whether RollCall can use your
   **Downloads** folder. Click **Allow**, so it can pick up event files you download from Facebook.

## Riding with friends

Set up once in the wizard's **Riding together** step (or **Settings → Riding together**): which app your
crew shares locations in (Find My, Life360, Google Maps or WhatsApp), your intercom (Cardo, Sena…) and
group, your crew's Discord invite, the tags you post under, and your handle. A group can have its own
Discord and tags on its Sources page.

Every ride then gets a **ride tag** like `#RCHalloweenPreMeet31Oct`, made from its name and date, so
everyone using RollCall gets the same one (a `#RC…` tag in someone's invite wins; you can also type
your own). Each ride's **Ride with friends** box has:

- **Before:** *Invite friends…* (share menu: Messages, AirDrop, Mail…, with a calendar file attached)
  and *Copy invite* to paste into Discord, WhatsApp or any group chat.
- **During:** *Open Discord*, *Open Find My* and *Directions*. Calendar events for rides you're going to
  carry the same crew card (map link, Discord, intercom group, location-sharing reminder, tags), and
  they sync to your phone, which is where you'll need them on the day.
- **After:** *Share footage…* (pick photos or videos, then the share menu, with the caption copied),
  *Copy caption & tags*, and *See posts* to open the tag on Instagram, TikTok or YouTube.

Why it stops there: Life360 and Cardo have no way for other apps to connect (no public API), so
RollCall can't show friends' locations or join an intercom group. Instagram, TikTok and Facebook don't
let Mac apps post for you, and RollCall only reads chats, never sends, so posting stays your tap.

## Updates

The code lives at https://github.com/MadisonDayerson/rollcall. Friends download RollCall from its
[latest release](https://github.com/MadisonDayerson/rollcall/releases/latest).

To ship a new version, open Terminal and run (with the version number and a line about what's new):

```bash
~/Downloads/Personal/RollCall/release.sh 1.1 "What's new in this version"
```

It runs the tests, sets the version, builds the .dmg, commits, tags, pushes and publishes a GitHub
release with the .dmg attached. Everyone's RollCall checks GitHub once a day (and from **Settings →
Updates → Check now**), offers **Update now**, then downloads the new version, swaps it in and reopens.
Updates installed this way skip the "Open Anyway" step. Because the app isn't signed with an Apple
Developer ID, macOS may ask for calendar access again after an update.

## Sharing RollCall with friends

```bash
~/Downloads/Personal/RollCall/build.sh --share
```

This makes `build/RollCall.dmg` (works on Apple silicon and Intel Macs, macOS 14 or newer) with
the app, an Applications shortcut and **How to open RollCall.txt**. Send the .dmg however you like.

RollCall isn't signed with an Apple Developer ID, so the first time a friend opens it their Mac
blocks it. They open it with **System Settings → Privacy & Security → Open Anyway** (the text file
walks them through it). Getting rid of that step needs a paid Apple Developer account ($149 AUD a
year) to sign and notarise the app.

The logo (white gothic RC on black, after Hooligoon's look) is drawn by `Design/make_icon.swift` with the
Bosieh font in `Design/fonts/bosieh` (free for personal, non-commercial use only; it's only used to draw
the icon, and isn't included in the app); run `swift Design/make_icon.swift Design/RollCall.png`
after changing it, and `build.sh` turns it into the app icon.

## Everyday use

Click the RC icon in the menu bar. The number next to it is how many new rides you haven't
decided on yet. The menu lists upcoming rides: hover over one to choose **Attending** (adds it to
Apple Calendar with a reminder the evening before), **Maybe** or **Skip**.

For everything else, choose **Open RollCall…** (⌘O). The window has four pages:

- **Rides**: every upcoming ride, with filters (To decide, All upcoming, Going, Skipped). Click a
  ride for its details, to choose Attending / Maybe / Skip, open the event page to RSVP, open the
  group page to join, or show the meeting place in Maps. Rides show 🆕 (new), 🔎 (date read from a
  post, so check it), ✅ (attending), 🤔 (maybe) or ✖︎ (skipped).
- **To review**:
  - **Possible plans**: conversations in your chats where someone mentions a time, day or date
    for a ride. Each shows a summary of the plan (what, when, where, who's in, what's still
    open), the conversation itself, and **Add as a ride…**, **Open in Beeper** or **Not a ride**.
  - **Posts without a day**: ride posts and invites that didn't say when. Open one, or click
    **Make a ride…** to turn it into a ride.
- **Sources**: everything RollCall gets rides from, in one list:
  - **Checked automatically** (every 3 hours): forums, websites, calendars, Meetup groups, news
    feeds and Beeper chats.
  - **Check yourself**: Instagram accounts, Facebook events and rides you added.

  Click a source to see its options. These depend on the kind of source, for example **Check now**,
  **Open website**, **Open chat in Beeper**, **Open on Instagram**, or the motorbike-only filter.
  Use **+** to add anything and **−** to remove the selected source.
- **Settings**: home area and distance, Beeper connection, Facebook downloads, open at login.

### Adding anything

Click **+** (in the toolbar or under the Sources list). Paste a link and click **Add link**.
RollCall works out what it is:

| You paste | What happens |
|---|---|
| A club or event website, forum section, Meetup group, calendar link or news feed | Added as a source that's checked automatically |
| A Facebook event link | Steps to bring in the event's details (below) |
| An Instagram account (`@name` or profile link) | Added to the accounts you check yourself |
| An Instagram post link | Opens the paste-a-post window to make a ride from it |

Or pick one of: **Watch chats** (WhatsApp and others, through Beeper), **Paste a post or message**,
**Type a ride in**, or **Import a calendar file**.

### Adding a Facebook event

1. Click **+** and paste the event's link (or Sources → Facebook events → **Add a Facebook event…**).
2. If it belongs to a group you want to join, you can add the group's link. On Facebook, click **Share → Copy link**. If the event belongs to a group
   you want to join, paste the group's link too.
3. Click **Open event page**. On Facebook, click **⋯** under the event title → **Add to calendar**
   → **Download** (Facebook sometimes calls this **Export event**).
4. Within a minute the ride appears in the menu with all its details.

If Facebook doesn't show that option, click **Type details instead** and fill in the name, time and
meeting place.

### Suggested sources in Victoria (offered in setup)

| Source | What it gives you |
|---|---|
| NetRider forum – VIC | New ride and event threads. Threads made from NetRider's calendar have exact times and places. For other threads the date is read from the post (marked 🔎). |
| NetRider forum – Ride & Event Announcements | The same, for national events (Distinguished Gentleman's Ride, Black Dog Ride…) |
| NetRider events calendar | Events posted in NetRider's calendar |
| Eventbrite – motorcycle events in Melbourne | Ticketed events that clearly mention motorbikes |
| Motorcycle Riders VIC (Meetup) | Group rides from this Meetup group |
| Instagram: @hooligoon.co | Opens in your browser (see below) |

Rides marked **🔎** had their date and place read from a post's text, so check the post before
going. Ride posts with no date in them go under **Posts to look at**.

### Instagram posts (Hooligoon and others)

1. Open RollCall → **Sources** → pick an account, such as @hooligoon.co, and click **Open on
   Instagram**. RollCall remembers when you last looked.
2. When a post announces a ride, select the caption and press ⌘C. Copying the post's link helps too.
3. Click **+** → **Paste a post or message**. The copied text is already filled in. Click **Next**.
4. RollCall fills in the date, time and meeting place it found. Check them, fix anything wrong,
   and click **Add**.

This works for any text: a forum post, a WhatsApp or Messenger message, an email or a poster you've
typed up. To add more accounts, click **+** and type `@account`.

### WhatsApp and other chats (through Beeper)

If WhatsApp (or Messenger, Signal, Telegram…) is connected in Beeper, RollCall can watch the
chats where people post rides.

1. Open **Beeper Desktop** → **Settings** (⌘,) → **Developers**, and check **Beeper Desktop API** is
   switched on.
2. In RollCall: click **+** → **Watch chats** (or Settings → Chats).
3. The first time, click **Open Beeper's page**. Your browser opens a Beeper page, then Beeper asks
   whether RollCall may read your chats. Switch to Beeper and click **Allow**. RollCall only asks
   to *read*, so it can't send, edit or delete anything. Then close the browser tab.
4. Tick the ride chats (group chats are at the top) and click **Watch these chats**.

RollCall reads the last month of messages straight away (events are often announced weeks ahead), then new messages every 3 hours while
Beeper is open. Messages never leave your Mac.

- When someone mentions a time, day or date ("Sunday", "this arvo", "8:30", "around 8ish", "15/11") in a
  conversation about riding, bikes or any motorbike event, RollCall gathers the messages around it (about an hour before and the replies
  after) and suggests you review it. You get a notification, and it appears under **To review**.
- The summary comes from **Apple Intelligence's on-device model**, so your messages never leave
  your Mac. It reads the whole back-and-forth, so a reply like "meet at Shell Coldstream 2pm" is
  combined with the earlier "ride this arvo?". If it decides the conversation isn't a ride plan, it
  stays out of your way. Without Apple Intelligence, RollCall makes its own best guess and only
  raises conversations that clearly plan a ride.
- Check the summary, then click **Add as a ride…**. The details are filled in for you to check.
  When the conversation moves on (a new time or place), the review updates and comes back.
- An invite without a day ("anyone keen for a ride soon?") goes under **Posts without a day**.
- Rides from watched chats show even if they're further than your distance setting.
- To change the chats, use **Change which chats…** on a chat in Sources, or Settings → Chats.
- If Beeper isn't open, the chat shows ⚠️ under **Sources** until next time.

### Adding a source

Click **+**, then paste a link to one of these:

- a **club or event website**. RollCall reads the events listed on the page, or uses the site's
  calendar feed if it has one.
- a **forum section**, such as another NetRider section or any other XenForo forum
- a blog or news feed (RSS)
- a **Meetup group** page. Public groups work straight away. Motorcycle Riders VIC is already
  added for you. A private group (for example Melbourne Twisty Tourers) needs your personal
  link: join the group, then on its Events tab choose the calendar / “Subscribe” option and paste
  the link it gives you.
- a club's **calendar link** (ends in `.ics` or starts with `webcal://`).
- a public **Google Calendar's** “Public address in iCal format”.

Sources are checked every 3 hours, or straight away with the ↻ button (all sources) or **Check now** on one source. RollCall is polite to
websites: it fetches one page at a time and reads each forum thread only once. Rides more than 100 km from
Melbourne are hidden. Change the distance under **Settings → Home area**.

## For tinkering

- `Sources/`: Swift source. `main.swift` is the menu bar and the actions, `Window.swift` is the window, `ICS.swift` reads calendar files,
  `Web.swift` reads web pages, RSS, forums and post text, `Beeper.swift` reads Beeper chats, `RidePlan.swift` reads days, times and places from messages, `Plans.swift` finds and summarises chat plans,
  `Refresh.swift` decides how each source is read, `CalendarSync.swift` talks to Apple Calendar, and `Model.swift` stores rides, choices and
  the built-in sources.
- Your data is saved in `~/Library/Application Support/RollCall/state.json`. The Beeper access
  token is in your login keychain (search Keychain Access for “motorides”).
- Run the tests:
  ```bash
  cd ~/Downloads/Personal/RollCall && swiftc Sources/ICS.swift Sources/Model.swift Sources/Sources.swift Sources/Web.swift Sources/Refresh.swift Sources/Beeper.swift Sources/RidePlan.swift Sources/Plans.swift Tests/main.swift -o build/tests && ./build/tests
  ```
- Save a picture of each page of the window (for checking the design):
  ```bash
  open ~/Applications/RollCall.app --args --snapshots ~/Desktop/motorides-snaps
  ```
- See which chat conversations would be raised for review, with their summaries (changes nothing;
  add `--all` to include plans that are already over):
  ```bash
  ~/Applications/RollCall.app/Contents/MacOS/RollCall --check-chats
  ```
- See what every built-in source finds right now:
  ```bash
  cd ~/Downloads/Personal/RollCall && swiftc Sources/ICS.swift Sources/Model.swift Sources/Sources.swift Sources/Web.swift Sources/Refresh.swift Sources/Beeper.swift Sources/RidePlan.swift Sources/Plans.swift Tests/live/main.swift -o build/live && ./build/live
  ```
