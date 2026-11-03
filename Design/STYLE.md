# RollCall's look

Taken from the icon: a white gothic "RC" on black, inside a thin double frame, like a club patch, with
"ROLLCALL" in spaced capitals underneath.

- **Black and white.** Text and marks use the system's text colours, so they invert for dark mode. Colour is
  kept for meaning only: warnings, problems, and the person's own accent colour on standard controls.
- **The patch.** A rounded rectangle with a thick outer line and a thin inner one (`DateBadge`). Each ride's
  date is one: filled for Going (like the icon), dashed for Maybe, outlined while undecided, faded when
  skipped or past, with a small ? when the date was read from a post.
- **Spaced capitals** (`PatchLabel`) for section headings, like "ROLLCALL" under the logo. Titles stay in
  bold sentence case, and everything else is the system font.
- **Gothic lettering, sparingly.** Only "Roll Call" at the foot of the sidebar and "RC" on empty pages
  (`Brand.wordmark`, `Brand.monogram`). They're pictures drawn by `make_wordmark.swift`, because the
  font's licence doesn't allow shipping it. Never use it for text people need to read.
