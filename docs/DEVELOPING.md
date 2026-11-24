# Developing RollCall

```bash
./build.sh --install                     # build, install in ~/Applications and open
./build.sh --share                       # build/RollCall.dmg for Apple silicon and Intel
./release.sh 1.1 "What's new"            # test, build, tag, push and publish a GitHub release
```

Run the tests:

```bash
./test.sh
```

- The code is in three folders: `Sources/Shared` (used by both apps: reading sources, rides, routes, calendar,
  sync), `Sources/Mac` (the Mac app's windows and menus) and `iOS/RollCall` (the iPhone and iPad screens).
  `./test.sh` also checks the iPhone app still builds, and `release.sh` gives both apps the same version number.
- Data is saved in `~/Library/Application Support/RollCall/state.json`; the Beeper token is in your
  login keychain.
- `--snapshots <folder>` saves a picture of every page; `--check-chats` shows how chat messages are read;
  `--check-details` shows what Refresh's search for more details finds.
- The logo is drawn by `Design/make_icon.swift` (see `Design/fonts/bosieh/ABOUT.txt` for the font).
- The app isn't signed with an Apple Developer ID, which is why the first open needs **Open Anyway**.
  Releases are signed with RollCall's own certificate instead (run `./make_signing_key.sh` once on the Mac
  that makes releases; `release.sh` won't run without it), so macOS treats every update as the same app and
  doesn't ask for keychain, calendar or Downloads access again. Without it, `build.sh` signs ad-hoc.

## iPhone and iPad

To put it on your own iPhone or iPad with a free Apple account:

1. Open `iOS/RollCall.xcodeproj` in Xcode.
2. Xcode → Settings → Apple Accounts → **+** → Apple Account, and sign in with your Apple ID.
3. Click the blue RollCall project at the top of the file list, choose the **RollCall** target, then
   **Signing & Capabilities**. Leave "Automatically manage signing" on and choose your name (Personal Team)
   under Team.
4. Plug the iPhone in with a cable, unlock it and tap **Trust** if it asks.
5. On the iPhone: Settings → Privacy & Security → **Developer Mode** → on, then restart it when asked.
6. In Xcode, choose the iPhone from the device menu at the top of the window and press ▶ (Run).
7. The first time, the iPhone says the developer isn't trusted: Settings → General → VPN & Device Management →
   your Apple ID → **Trust**. Then open RollCall.

With a free account the app stops opening after 7 days: plug in and press ▶ again to renew it.
