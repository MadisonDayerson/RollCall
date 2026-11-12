# RollCall's look

Taken from the icon: a white gothic "RC" on black, inside a thin double frame, like a club patch, with
"ROLLCALL" in spaced capitals underneath.

- **Black and white.** Text and marks use the system's text colours, so they invert for dark mode. Colour is
  kept for meaning and for Apple's standard controls: the person's own accent colour on the sidebar, filled
  buttons and links (as Apple's guidelines expect), orange for warnings and problems, and one neon blue glow: while the sources are checked, the sidebar's "Roll Call"
  fills with glowing blue letters from left to right as a progress bar, then pulses blue when it's done (`Wordmark`).
  Nothing else is coloured.
  The selected ride in the list is a light grey band with rounded corners, so the list stays black and white.
- **The patch.** A rounded rectangle with a single 1.5pt line (`DateBadge`, which stays crisp), kept simple so a list of
  rides stays clean. The day is in heavy condensed numbers, the month and weekday in small bold capitals. Each ride's
  date is one: filled for Going (like the icon), dashed for Maybe, outlined while undecided, faded when
  skipped or past, with a small ? when the date was read from a post.
- **Short buttons.** One or two words, a verb where it helps ("Open event", "Edit…", "Route", "Remove"). The
  heading or page already says what it's about, and anything more goes in the tooltip (`.help`). Longer only where
  it's clearer: the setup guide's steps ("I've installed it"), "Not a ride" and "Delete all data…".
- **Spaced capitals** (`PatchLabel`) for section headings, like "ROLLCALL" under the logo. Titles stay in
  bold sentence case, and everything else is the system font.
- **Maps in greys.** Route maps use Apple's muted map turned to greys, with the route in the text colour, so they
  sit in the black and white.
- **Gothic lettering, sparingly.** Only "Roll Call" at the foot of the sidebar and at the top of every dialog
  (in place of the app icon, `Dialogs.run`), and "RC" on empty pages
  (`Brand.wordmark`, `Brand.monogram`). They're pictures drawn by `make_wordmark.swift`, because the
  font's licence doesn't allow shipping it. Never use it for text people need to read, numbers included.
