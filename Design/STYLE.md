# RollCall's look

Taken from the icon: a white gothic "RC" on black, inside a thin double frame, like a club patch, with
"ROLLCALL" in spaced capitals underneath.

- **Black and white.** Text and marks use the system's text colours, so they invert for dark mode. Colour is
  kept for meaning only: warnings, problems, and the person's own accent colour on standard controls.
- **The patch.** A rounded rectangle with a single 1.5pt line (`DateBadge`, which stays crisp), kept simple so a list of
  rides stays clean. The day is in the logo's gothic digits, the month and weekday in small bold capitals. Each ride's
  date is one: filled for Going (like the icon), dashed for Maybe, outlined while undecided, faded when
  skipped or past, with a small ? when the date was read from a post.
- **Short buttons.** One or two words, a verb where it helps ("Open event", "Edit…", "Route", "Remove"). The
  heading or page already says what it's about, and anything more goes in the tooltip (`.help`).
- **Spaced capitals** (`PatchLabel`) for section headings, like "ROLLCALL" under the logo. Titles stay in
  bold sentence case, and everything else is the system font.
- **Gothic lettering, sparingly.** Only "Roll Call" at the foot of the sidebar, "RC" on empty pages and the day
  number on date patches (`Brand.wordmark`, `Brand.monogram`, `Brand.digits`). They're pictures drawn by
  `make_wordmark.swift` and `make_digits.swift`, because the font's licence doesn't allow shipping it. Never
  use it for words; numbers are clear enough in it.
