# rootyapps — monorepo

Each `<app>.swift/` is a standalone app. `marketing/` is a SHARED library used by all of them.

## Shared marketing library — read before touching store assets

- `marketing/autoaso.md` — ASO agent instructions. **§6.5 hard-won ASO rules** and
  **§6.6 multilingual pipeline** (folder layout, tofu, stale outputs, ASC write paths) are
  do-not-relearn sections. Read them before generating metadata or media.
- `marketing/screenshots_generator/README.md` — screenshot framing; multi-language folder layout.
- `marketing/reels/README.md` — preview/reel capture. Framed reels are NEVER app previews (2.3.4).
- `marketing/logic/README.md` — App Store Connect API: which endpoint owns which field, and where
  the submit boundary is.

**Never fork these scripts into an app directory.** Every app calls them in place; a copy silently
stops receiving fixes. The same font-coverage bug shipped three times because three renderers each
had a private font helper.

## Store assets

- Localized TEXT: do every locale (cheap, compounds in search). Localized MEDIA: a chosen subset.
- A screenshot freezes the build it was taken from — re-capture after any string or UI change.
- Draft and stage only. Creating a version, submitting, changing price, and assigning a build to an
  external TestFlight group are human decisions — ask first.
