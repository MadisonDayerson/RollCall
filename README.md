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
5. **Riding together:** your crew's location app, voice chat, Discord and tags
   (see [Riding with friends](#riding-with-friends)).

## Everyday use

Click **RC** in the menu bar to see upcoming rides and mark them **Going**, **Maybe** or **Skip**.
Going adds the ride to your **RollCall** calendar, with a reminder the evening before.

The full window opens when you open RollCall (or choose **Open RollCall…** in the menu). While it's open,
RollCall has its own menus at the top of the screen, and ⌘1–⌘4 switch pages:

- **Rides:** a ride posted in several places (say, Facebook and a forum) shows once, with every place under
  **From**. **All** shows Undecided (including Maybe), Going, Skipped and Past in sections you can fold away. Click a
  ride for a plain summary of the description (**See more** shows all of it), the event page (to RSVP), the
  group page (to join) and the route. A ? on the date means it was read from a post, so double-check it.
  Rides you went on move to **Past** once they're over.
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
| Instagram post, or any post or message | Opens **Paste post** to make a ride from it |

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

New to Beeper? In setup's **Chats** step, click **Set up Beeper**. RollCall walks you
through each step below in plain language and checks each one for you.

1. Install Beeper and connect your chat accounts in **Beeper → Settings → Accounts**.
2. In Beeper, open **Settings → Developers** and switch on **Beeper Desktop API**.
3. In RollCall, click **+** → **Check chats**, click **Allow** in Beeper, then tick your ride chats.

When a chat mentions a day or time for a ride or bike event, RollCall sums up the plan (what, when,
where, who's in) and asks you to review it. A message sent to several of your chats shows once. **Add ride…** has Apple Intelligence read the conversation and fill in the name, start, length, meeting place, link and notes (destination and stops) for you to check. Summaries use
Apple Intelligence on your Mac where available. Beeper needs to be open for chats to be checked.

## Riding with friends

Each ride's page starts with its status, then **About**: when, where, who it's from and a plain summary of the
description. Under it, every ride has the same buttons: **Open event**, **Edit…**, **Route**, **Join group** and
**Remove** (one that can't do anything yet is greyed out and says why). **Join group** asks for the group's link the
first time. **Remove** takes the ride away for good, even if its source still lists it. **Edit…** changes the name, time, length, place,
link or notes; your changes stay when RollCall checks the source again, and go to the calendar for rides you're going to. **Route** opens the organiser's route if the
description has one, otherwise directions from your suburb through the meeting place and stops.

The calendar event for a ride you're going to includes the map link, your crew's Discord, voice chat group and a
location-sharing reminder.

**Voice chat** (Settings → Riding together) is your helmet intercom (Cardo, Sena, Interphone, UClear, Midland,
FreedConn, LEXIN) or a call (Discord voice, WhatsApp). Intercoms pair with your phone, not your Mac, so set up
the group in its phone app and add the group or channel name: calendar events then say which to join.

Every ride gets a code tag of #RC and the date, like `#RC03112026`, the same for everyone using RollCall.
Tags for the club, brand, place or occasion follow it (`#Hooligoon #TTR #Broadford #Halloween`). They're in the
calendar event, so everyone tags their photos and videos the same way.

Life360, Cardo and the social apps don't let other apps connect, so RollCall puts the details and
tags in the calendar event rather than showing friends' locations or posting for you.

## Your privacy

- **No accounts, no tracking, no AI services.** RollCall has no server of its own. It doesn't collect or
  send anything about you, and nobody else using RollCall can see your rides, chats or settings.
- **Chats stay on your Mac.** They're read through Beeper Desktop on your own Mac, with read-only permission.
  The Beeper key is kept in your keychain. Chat plans are summarised by Apple's on-device model (when Apple
  Intelligence is on), so messages never go to an online AI. Before the model reads them, swearing is left out, tracking is taken off links and long
  conversations are trimmed to the messages that matter; your messages themselves aren't changed.
- **Saved rides are private.** They're in `~/Library/Application Support/RollCall`, which only your Mac
  account can open. RollCall keeps no web cache or cookies.
- **Only what's needed is kept.** Your home area is saved as just the suburb and a rough spot (about 1 km).
  Messages from conversations you dismiss aren't kept, removing a chat removes what was kept from it, and
  past rides you didn't go to are removed after a week.
- **You're in control.** Settings → Privacy → **Delete all data** removes everything RollCall kept
  on your Mac and disconnects Beeper.
- **What goes online.** RollCall only downloads the pages and calendars on your Sources list, with no cookies
  or details about you. It asks Apple Maps where a ride's location is, so it can work out the distance. And
  it checks this project's GitHub page for updates. An update is only installed if it comes from those
  releases and its seal shows it hasn't been changed. When you click **Route**, your suburb
  (never your street) and the ride's stops go to your maps app (Apple Maps, Google Maps or Waze) to plan the route.
- **What you share.** Rides you're going to are added to the RollCall calendar, in the calendar account you
  choose. Text from chat messages isn't added.

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
./test.sh
```

- Data is saved in `~/Library/Application Support/RollCall/state.json`; the Beeper token is in your
  login keychain.
- `--snapshots <folder>` saves a picture of every page; `--check-chats` shows how chat messages are read.
- The logo is drawn by `Design/make_icon.swift` (see `Design/fonts/bosieh/ABOUT.txt` for the font).
- The app isn't signed with an Apple Developer ID, which is why first opens need **Open Anyway** and
  macOS may ask for calendar access again after an update.
