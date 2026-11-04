# RollCall bug list

From a play-test on 5 November 2026 (build after commit a3d0c6a). Found with snapshots of every page at
1100×760, 800×560 and 560×700 in dark mode, a live read of every website and calendar source against a copy of
the saved data, the `--check-chats` tool, and a read-through of each flow. Nothing was clicked in the running app
(no desktop control in that session), so the click-through checks at the end are still to do.

## Fixed

- All-day rides counted as over on the morning of the ride: rides now have one finish time, the end of the
  last day for all-day rides.
- Editing a cross-posted ride could split it back into two: the edit now goes to every copy.
- Settings read the keychain every time it was drawn: the Beeper key is read once and remembered.
- Setup's ordinary buttons were nearly invisible in dark mode: only the filled buttons are tinted now.
- A chat source's page was cut off in a smaller window: its buttons and the "Check for new rides" menu wrap.
- Outdated "invites and captions" wording, the Facebook box pointing to the Sources page while on it, the
  cut-off "Paste a new link to replace it" hint, and "Choose chats…" when chats are already chosen.

## Checked, nothing to fix

- **Meetup's empty reply.** RollCall already marks a reply without a calendar in it as a problem on the source
  ("That link isn't a calendar feed"). On 5 November the link answered with a proper, empty calendar: the group
  has nothing coming up.
- **How long chat checks take.** A one-day `--check-chats` over all 9 chats took about 2 minutes, with every
  conversation in that day summarised. The app's 15-minute check only summarises conversations with new
  messages, so it does less than that, and a check that runs long is never started twice.

## Still to play-test by hand

These need clicks in the running app:
- Going / Maybe / Skip on a ride, then the calendar event appears, changes after an Edit, and goes after Remove.
- Remove on an upcoming ride from a website, then Check all sources now: it should stay gone.
- Add ride… from a chat plan: the form fills in, and Save adds the ride.
- Paste a post (+ → Paste a post or message) and Type a ride in.
- The menu bar's ride submenu: each of Open event, Edit…, Route, Remove.
- Light mode (every snapshot came out dark because the Mac is in dark mode; `--dark` only forces dark).
