<img src="Design/RollCall.png" alt="RollCall logo" width="160">

# RollCall

RollCall is a Mac menu bar app that finds motorbike group rides and events near you, from clubs, forums,
event sites, Meetup and your group chats. Pick **Going** and the ride goes into your calendar.

- **One list of rides.** A ride posted in several places shows once.
- **Your group chats too.** Plans made in WhatsApp, Messenger or Messages are picked out for you to review.
- **The route, ready to go.** Map, distance, weather along the way and (in Victoria) road alerts.
- **Private.** No accounts or tracking. RollCall never posts, sends messages or RSVPs for you.

## Install

Needs macOS 14 or newer (Apple silicon or Intel).

1. Download **RollCall.dmg** from the [latest release](https://github.com/MadisonDayerson/RollCall/releases/latest).
2. Open it and drag **RollCall** into **Applications**.
3. Open RollCall. The first time, your Mac blocks it because it isn't from the App Store:
   go to **System Settings → Privacy & Security**, click **Open Anyway**, and enter your password.

A setup guide then takes you through your area, chats, groups and calendar. Open it again any time with
**Set up RollCall…** in the menu. RollCall updates itself: choose **Update now** in the menu.

## Using it

- Click **RC** in the menu bar and choose **Open RollCall…** for the full window. **Home** shows your next ride, this
  week and next, and rides to decide on; **Rides** lists them all, or shows a week or month. Mark each ride **Going**,
  **Maybe** or **Skip** there.
- Click **+** to add a ride (a poster, a post, a calendar file or your own) or a source to keep checking.

The [guide](docs/GUIDE.md) covers the rest: [group chats](docs/GUIDE.md#group-chats),
[Facebook and Instagram](docs/GUIDE.md#facebook-and-instagram), [routes and weather](docs/GUIDE.md#routes-and-weather),
[road alerts](docs/GUIDE.md#road-alerts), [riding together](docs/GUIDE.md#riding-together) and
[sharing with iPhone and iPad](docs/GUIDE.md#iphone-and-ipad).

## Your privacy

- Your rides, choices and settings stay on your Mac. RollCall has no server, and no one else using it can see them.
- Chats are read-only and only the ones you choose. They're read by Apple's on-device model, never an online AI.
- RollCall goes online only for what it needs: your sources, maps, weather, road alerts and updates.
- If you turn on sharing, your rides and sources reach your own iPhone and iPad through your iCloud Drive, without
  chat messages.
- **Settings → Privacy → Delete all data** removes everything RollCall kept on your Mac.

[Privacy in detail](docs/PRIVACY.md) lists exactly what's kept, for how long, and what goes online.
To report a security problem, see [SECURITY.md](SECURITY.md).

## iPhone and iPad (in progress)

There's an early iPhone and iPad version that you build yourself in Xcode: see
[how to install it](docs/DEVELOPING.md#iphone-and-ipad).

## For developers

Build with `./build.sh --install` and test with `./test.sh`. More is in [docs/DEVELOPING.md](docs/DEVELOPING.md).
