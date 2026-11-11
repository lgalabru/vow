# Rehearsal

Stageshow scenes on the landing page: the hero iPad (`device.tsx`) and the five
feature tiles (`bento.tsx`).

- **Started from:** `examples/bento` (hero and strip, one Stage per tile, one
  beat each, played once in reading order) and the `phone-touch` conventions for
  the touch cursor. The kit has no tablet frame, so the iPad mini is drawn in
  CSS at the device's real proportions (1256 x 867 pt body, 62 pt band).
- **Changed:** Vow's content and look (white ground, round tiles, black and
  green on the page, iPadOS blue inside the device). The hero loop ends by
  advancing to the next sample request, so it resets with a visible cause.
- **Filmed:** `scripts/film.mjs --gate` against the production build, hero and
  tiles, at 1280 and 390 wide.
  - Tiles: no findings at either width apart from `kit override`.
  - Hero at 1280: no findings apart from `kit override`.
  - `kit override` (six lines per stage) is the kit's own CSS: Next bundles it
    into hashed chunks, so the check cannot tell it from the site's. The site's
    CSS sets no size or position on a guarded kit part.
- **Not passing, accepted:** at 390 the hero reports `shrunk, not laid out for
the phone` (the whole iPad is kept in view, drawn at 0.56, text about 10px)
  and one `loose list` on the signature sheet.
- **Not checked:** Safari and Firefox, dark mode (the page is light only), and
  the scene against the current native build's exact layout.
