# Security

## Reporting a problem

If you find a security or privacy problem in RollCall, please report it privately. On GitHub, open the
**Security** tab of this repository and choose **Report a vulnerability**. Please don't open a public issue,
and don't include anyone's real chat messages, addresses or keys in a report.

Reports are read by the maintainer, a hobbyist, so there's no fixed response time. A fix goes out as a new
release, and everyone's RollCall offers it within a day.

## Supported versions

Only the latest release gets fixes. RollCall checks for updates by itself (Settings → Updates), so keep
that switched on.

## How RollCall protects your data

- Rides, chat excerpts, sources and settings are saved on your Mac, in
  `~/Library/Application Support/RollCall`, which only your Mac account can open. Rides, choices and sources (never chat
  messages) are also in your own iCloud Drive if you turn on sharing with your iPhone and iPad. Nothing is sent to a
  server of RollCall's (there isn't one), to an online AI, or to other people using RollCall.
- The Beeper key (read-only permission) and the road alerts key are kept in the keychain. RollCall never sends
  messages or posts anything.
- RollCall keeps no web cache or cookies. Internet connections use HTTPS, except the connection to Beeper
  Desktop, which stays inside your Mac.
- RollCall keeps only what it needs. Your home area is saved as a suburb and a rough spot (about 1 km).
  Past rides, and the messages of plans you mark Not a ride, are deleted after a week (or as Settings → Privacy says,
  two weeks at most), and removing a chat removes what was kept from it.
- Settings → Privacy → **Delete all data** removes everything RollCall kept on your Mac.
- Updates are only downloaded from this repository's releases, and only installed if the app's code seal
  shows it hasn't been changed.
