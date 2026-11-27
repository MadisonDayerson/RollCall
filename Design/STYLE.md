# RollCall's look

Taken from the icon: a white gothic "RC" on black, inside a thin double frame, like a club patch, with
"ROLLCALL" in spaced capitals underneath.

- **Black and white.** Text and marks use the system's text colours, so they invert for dark mode. Colour is
  kept for meaning and for Apple's standard controls: the person's own accent colour on the sidebar, filled
  buttons and links (as Apple's guidelines expect), orange for warnings and problems, and one neon blue glow
  (`Neon`), which also glows faintly behind the glass cards (below): while the sources are checked, the sidebar's "Roll Call" fills with glowing blue letters from left to right as a progress bar, then pulses blue when it's done (`Wordmark`).
  On iPhone and iPad it's in the space above Home and the rides list while that's pulled down to refresh, in place of a spinner.
  It stays grey there until the pull is long enough to refresh.
  The same blue lights the lettering as RollCall opens on iPhone and iPad (once, not when it comes back): the lettering bursts out of a blast of blue flame and embers, stays long enough to read, then a low fire sweeps it away from left to
  right, with its small embers (`Splash`, `Fire`).
  Nothing else is coloured.
  The selected ride in the list is a light grey band with rounded corners, so the list stays black and white.
- **The patch.** A rounded rectangle with a single 1.5pt line (`DateBadge`, which stays crisp), kept simple so a list of
  rides stays clean. The day is in heavy condensed numbers, the month and weekday in small bold capitals. Each ride's
  date is one: filled for Going (like the icon), dashed for Maybe, outlined while undecided, faded when
  skipped or past, with a small ? when the date was read from a post. On iPhone and iPad, the week and month show days
  with rides the same way, with a line under today's number.
- **Short buttons.** One or two words, a verb where it helps ("Open event", "Edit…", "Route", "Remove"). The
  heading or page already says what it's about, and anything more goes in the tooltip (`.help`). Longer only where
  it's clearer: the setup guide's steps ("I've installed it"), "Not a ride" and "Delete all data…".
- **Spaced capitals** (`PatchLabel`) for section headings, like "ROLLCALL" under the logo. Titles stay in
  bold sentence case, and everything else is the system font.
- **Maps in greys.** Route maps use Apple's muted map turned to greys, with the route in the text colour, so they
  sit in the black and white.
- **Glass for controls and Home's cards.** On macOS 26 the sidebar, toolbar and dialogs are Apple's Liquid Glass by themselves,
  and so are the buttons that float over a page (`glassButton`: the drawer's Back, setup's Back and Continue). The cards on
  Home and the Rides calendar are glass too (`glassCard`), over a faint neon glow so the glass has something to bend
  (`glassBackdrop`); the glass is behind what's on them, so date patches keep their full black and white. Lists, plans,
  dates and text stay plain, and glass is never put on glass: a card's own buttons are ordinary ones. Tabs and setup's steps
  sit in bars the page scrolls under (`floatingBar`), with a clear edge so they can be read over it. The main button is
  black, or white in dark mode, like the logo. Boxes have rounded corners (`Brand.card`, `.panel`, `.note`). Older
  macOS gets ordinary buttons and bars.
  On iPhone and iPad the tab bar (which shrinks as a page is scrolled), title bars and menus are glass by themselves, and so
  are setup's wide button, in the same black or white, and the note while a source is read. A page's views are chosen from
  its title bar (Rides' List, Week and Month), and a question before removing something opens from what was tapped. A
  spinner isn't a control, so it has no glass. Cards' corners match Apple's lists, and the map's follow its card's.
  The icon there is in layers (`iOS/RollCall/AppIcon.icon`, drawn by `make_phone_icon.swift`), which iOS lights, darkens and tints.
- **Gothic lettering, sparingly.** Only "Roll Call" at the foot of the sidebar, above Home and the rides list on iPhone and iPad, and at the top of every dialog
  (in place of the app icon, `Dialogs.run`), "RC" on empty pages,
  and "RC" over "RollCall" as RollCall opens on iPhone and iPad (`Brand.wordmark`, `Brand.monogram`, `Splash`). They're pictures drawn by `make_wordmark.swift`, because the
  font's licence doesn't allow shipping it. Never use it for text people need to read, numbers included.
