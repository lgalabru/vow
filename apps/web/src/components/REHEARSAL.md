# Rehearsal

Stageshow scenes on the landing page: the pinned iPad story (`factors.tsx`), the
feature tiles (`bento.tsx`) and the Mac companion window (`mac.tsx`).

- **Started from:** `examples/bento` for the one-window tile with a corner bleed
  (the Mac section). The iPad story has no gold equivalent: its stage has no
  script, and the page's scroll position sets the scene instead. The kit has no
  tablet frame, so the iPad mini is drawn in CSS at the device's real
  proportions (1256 x 867 pt body, 62 pt band).
- **Looked at:** screenshots of every chapter at 1440 x 900 and of the story at
  390 x 844.
- **Not filmed:** `scripts/film.mjs --gate` was run on the earlier looping hero
  and an earlier five-tile grid, not on the scenes as they are now. The film samples a script over time, and the story
  only moves when the page scrolls.
- **Known:** on a phone the landscape iPad is about 300px wide, so its screen
  text is too small to read comfortably.
- **Not checked:** Safari and Firefox, dark mode (the page is light only), and
  the scenes against the current native builds' exact layout.
