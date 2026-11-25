# Privacy in detail

- **No accounts, no tracking, no AI services.** RollCall has no server of its own. It doesn't collect or
  send anything about you, and nobody else using RollCall can see your rides, chats or settings.
- **Chats stay on your Mac.** They're read through Beeper Desktop on your own Mac, with read-only permission.
  Only the last two weeks of messages are read (older chat is no longer relevant), and after the first time
  just the messages since the last check; forums and news feeds are read back two weeks too. The Beeper key is kept in your keychain. Chat plans are summarised by Apple's on-device model (when Apple
  Intelligence is on), so messages never go to an online AI. The same on-device model reads ride descriptions to
  find their start, stops and destination. Before the model reads them, swearing is left out, tracking is taken off links and long
  conversations are trimmed to the messages that matter; your messages themselves aren't changed.
- **Saved rides are private.** They're in `~/Library/Application Support/RollCall`, which only your Mac
  account can open. RollCall keeps no web cache or cookies.
- **Only what's needed is kept.** Your home area is saved as just the suburb and a rough spot (about 1 km).
  Past rides, and the messages from plans you mark Not a ride, are deleted after a week (or straight away, or
  after a day or two weeks at most: choose in Settings → Privacy). Calendar events stay in Calendar. Posts and
  conversations waiting to be looked at go after two weeks, and places are only remembered for rides RollCall
  still has. Removing a chat removes what was kept from it.
- **You're in control.** Settings → Privacy → **Delete all data** removes everything RollCall kept
  on your Mac and disconnects Beeper, and takes away the file it shares with your iPhone and iPad. The iPhone and iPad
  app's own **Delete all data** does the same there.
- **What goes online.** Only this, with no cookies or details about you:
  - **Sources:** the pages and calendars on your Sources list. **Refresh** also downloads the event pages of the rides
    it looks for more details about (never Facebook or Instagram).
  - **Maps:** RollCall asks Apple Maps where a ride is, to work out the distance (a match more than 1000 km away is taken
    as not found, since it's another place with the same name), and for the road route between a ride's places. It follows
    a short Google Maps link (maps.app.goo.gl) in a ride's description once, to find the route it points to.
  - **Opening a route:** your suburb (never your street) and the ride's stops go to your maps app (Apple Maps, Google
    Maps, Waze or Kurviger).
  - **Weather:** the positions of a few points on the route (not the ride or anything about you) go to Open-Meteo, a free
    forecast service.
  - **Road alerts:** with a key, RollCall downloads all of Victoria's road alerts from the Department of Transport and
    Planning and matches them to the route on your Mac, so the route isn't sent. Your key is kept in your keychain.
    Booked roadworks are kept on your Mac between downloads; they're public road data, nothing about you.
  - **Updates:** it checks this project's GitHub page. An update is only installed if it comes from those releases and
    its seal shows it hasn't been changed.
- **Sharing with your iPhone and iPad** (only if you turn it on). Your rides, choices, ride changes, sources
  (including private calendar links), riding-together details and how long past rides are kept go to a RollCall folder in your own iCloud Drive, where RollCall on your
  iPhone and iPad reads them. Chat messages don't: rides from chats, and your changes to them, are shared without them.
  Turning sharing off leaves the folder in iCloud Drive, for when you turn it on again; delete it there if you don't want it.
- **What you share.** Rides you're going to are added to the RollCall calendar, in the calendar account you
  choose. Text from chat messages isn't added, except a detail Refresh found that you add yourself.

RollCall is made to follow the Australian Privacy Principles: it only collects what it needs, keeps it
secure, and deletes it when it's no longer needed. To report a security problem, see [SECURITY.md](../SECURITY.md).
