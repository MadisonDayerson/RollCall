# RollCall

![RollCall logo](Design/RollCall.png)

RollCall is a Mac menu bar app that finds motorbike group rides and events near you, from clubs,
forums, event sites, Meetup and your group chats. Pick **Going** and the ride goes into your calendar.

Everything stays on your Mac. RollCall never posts, sends messages or RSVPs for you.

## Install

Needs macOS 14 or newer (Apple silicon or Intel).

1. Download **RollCall.dmg** from the [latest release](https://github.com/MadisonDayerson/RollCall/releases/latest).
2. Open it and drag **RollCall** into **Applications**.
3. Open RollCall. The first time, your Mac blocks it because it isn't from the App Store:
   go to **System Settings → Privacy & Security**, click **Open Anyway**, and enter your password.

RollCall updates itself: when a new version is out, choose **Update now** in the menu.

## Set up

A setup guide opens the first time (re-open it any time with **Set up RollCall…** in the menu):

1. **Your area:** your suburb or town, and how far you'll travel.
2. **Chats:** connect group chats through the free [Beeper](https://www.beeper.com/download) app
   (see [Group chats](#group-chats)).
3. **Groups & accounts:** pick from suggestions for your area, or paste any link or `@instagram` name.
4. **Calendar:** allow access, then choose iCloud, Google, Exchange or this Mac.
   For Google, first add your Google account in **System Settings → Internet Accounts**.
5. **Riding together:** your crew's location app, intercom, Discord and tags
   (see [Riding with friends](#riding-with-friends)).

## Everyday use

Click **RC** in the menu bar to see upcoming rides and mark them **Going**, **Maybe** or **Skip**.
Going adds the ride to your **RollCall** calendar, with a reminder the evening before.

The full window opens when you open RollCall (or choose **Open RollCall…** in the menu). While it's open,
RollCall has its own menus at the top of the screen, and ⌘1–⌘4 switch pages:

- **Rides:** **All** shows Undecided (including Maybe), Going, Skipped and Past in sections you can fold away. Click a
  ride for details, the event page (to RSVP), the group page (to join) and directions. A ? on the date means it was read from a post, so double-check it.
  Rides you went on move to **Past** once they're over, so you can still share footage and find
  everyone's posts with the ride's tag.
- **To review:** possible ride plans from your chats, plus ride posts that didn't say when.
- **Sources:** everything RollCall reads, grouped by app (click a heading to fold it away). Chats are
  checked every 15 minutes, calendars every 3 hours, and websites and forums every 6 hours; change
  any of them with **Check for new rides** (right-click a heading to change a whole group).
  Instagram and Facebook you check yourself.
- **Settings:** home area, chats, your Facebook events link, calendar, riding together and updates.

## Adding rides and sources

Click **+** and paste a link. RollCall works out what it is:

| Paste | Result |
|---|---|
| Club or event website, forum section, Meetup group, calendar link (`.ics`, `webcal://`) or news feed | Checked automatically |
| Facebook event, or your Facebook events calendar link | Follow the steps below |
| Instagram account (`@name`) | Added to the accounts you check |
| Instagram post, or any post or message | Opens **Paste a post** to make a ride from it |

You can also **Type a ride in** or **Import a calendar file**.

**Your Facebook events.** Facebook can share a private calendar of the events you're Going or Interested
in. Connect it in setup's **Groups & accounts** step, in **Settings → Facebook** (where you can also replace
or disconnect it), or under **Sources → Facebook events**:
1. Click **Open Facebook Events**, find **Add to calendar**, right-click it and choose **Copy Link**.
2. Paste the link into RollCall and click **Connect**. Bike events you respond to then come in by themselves.

Keep that link to yourself: anyone who has it can see your events.

**One Facebook event at a time** (events you haven't responded to, or if the calendar link stops working):
1. Click **+** and paste the event link, then click **Open event page**.
2. On Facebook, click **⋯** → **Add to calendar** → **Download**.
3. The ride appears in RollCall within a minute. (Allow access to Downloads if asked.)

**Instagram posts.** Instagram doesn't let apps read posts, so open the account from **Sources**,
copy a ride post's caption (⌘C), then click **+** → **Paste a post or message**. RollCall fills in
the date, time and place for you to check.

## Group chats

WhatsApp, Messenger and Messages don't let other apps read chats. [Beeper](https://www.beeper.com/download)
brings them into one app and lets RollCall read only the chats you choose, read-only.

New to Beeper? In setup's **Chats** step, click **Set up Beeper step by step**. RollCall walks you
through each step below in plain language and checks each one for you.

1. Install Beeper and connect your chat accounts in **Beeper → Settings → Accounts**.
2. In Beeper, open **Settings → Developers** and switch on **Beeper Desktop API**.
3. In RollCall, click **+** → **Check chats**, click **Allow** in Beeper, then tick your ride chats.

When a chat mentions a day or time for a ride or bike event, RollCall sums up the plan (what, when,
where, who's in) and asks you to review it. **Add as a ride…** fills in the details. Summaries use
Apple Intelligence on your Mac where available. Beeper needs to be open for chats to be checked.

## Riding with friends

Each ride's **Ride with friends** box helps the whole crew end up in the same places:

- **Before:** **Invite friends…** or **Copy invite** for Discord or a group chat. Invites include
  the time, meeting point, map link, Discord, intercom group and a location-sharing reminder.
- **During:** the same details are in the calendar event on your phone, plus buttons for Discord,
  Find My and directions.
- **After:** **Share footage…** or **Copy caption & tags**, and **See posts** to find everyone else's.

Every ride gets a code tag of #RC and the date, like `#RC03112026`, the same for everyone using RollCall.
Tags for the club, brand, place or occasion follow it (`#Hooligoon #TTR #Broadford #Halloween`); change them on the
ride's page.

Life360, Cardo and the social apps don't let other apps connect, so RollCall shares the details and
tags rather than showing friends' locations or posting for you.

## Your privacy

- **No accounts, no tracking, no AI services.** RollCall has no server of its own. It doesn't collect or
  send anything about you, and nobody else using RollCall can see your rides, chats or settings.
- **Chats stay on your Mac.** They're read through Beeper Desktop on your own Mac, with read-only permission.
  The Beeper key is kept in your keychain. Chat plans are summarised by Apple's on-device model (when Apple
  Intelligence is on), so messages never go to an online AI.
- **Saved rides are private.** They're in `~/Library/Application Support/RollCall`, which only your Mac
  account can open. RollCall keeps no web cache or cookies.
- **Only what's needed is kept.** Your home area is saved as just the suburb and a rough spot (about 1 km).
  Messages from conversations you dismiss aren't kept, removing a chat removes what was kept from it, and
  past rides you didn't go to are removed after a week.
- **You're in control.** Settings → Privacy → **Delete all RollCall data** removes everything RollCall kept
  on your Mac and disconnects Beeper.
- **What goes online.** RollCall only downloads the pages and calendars on your Sources list, with no cookies
  or details about you. It asks Apple Maps where a ride's location is, so it can work out the distance. And
  it checks this project's GitHub page for updates. An update is only installed if it comes from those
  releases and its seal shows it hasn't been changed.
- **What you share.** Rides you're going to are added to the RollCall calendar, in the calendar account you
  choose. Text from chat messages isn't added. The invites and captions you copy only go where you paste them.

RollCall is made to follow the Australian Privacy Principles: it only collects what it needs, keeps it
secure, and deletes it when it's no longer needed. To report a security problem, see [SECURITY.md](SECURITY.md).

## For developers

```bash
./build.sh --install                     # build, install in ~/Applications and open
./build.sh --share                       # build/RollCall.dmg for Apple silicon and Intel
./release.sh 1.1 "What's new"            # test, build, tag, push and publish a GitHub release
```

Run the tests:

```bash
swiftc Sources/ICS.swift Sources/Model.swift Sources/Sources.swift Sources/Web.swift Sources/Refresh.swift Sources/Beeper.swift Sources/RidePlan.swift Sources/Plans.swift Sources/Crew.swift Sources/Updater.swift Tests/main.swift -o build/tests && build/tests
```

- Data is saved in `~/Library/Application Support/RollCall/state.json`; the Beeper token is in your
  login keychain.
- `--snapshots <folder>` saves a picture of every page; `--check-chats` shows how chat messages are read.
- The logo is drawn by `Design/make_icon.swift` (see `Design/fonts/bosieh/ABOUT.txt` for the font).
- The app isn't signed with an Apple Developer ID, which is why first opens need **Open Anyway** and
  macOS may ask for calendar access again after an update.
