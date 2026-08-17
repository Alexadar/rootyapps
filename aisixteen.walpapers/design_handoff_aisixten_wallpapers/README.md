# Handoff: AISixten Wallpapers — on-device AI wallpaper generator

## Overview
A two-screen universal app (iPhone / iPad / Mac): **Create** (prompt → on-device diffusion → wallpaper) and **Gallery** (everything generated, stored in the app's iCloud Drive folder). No account, no network after first run, no monetization UI. Plus a one-time **first-run gate**: consent + download of the ML model as an Apple-Hosted Background Asset.

## Round 3 — the five live problems (board turn 6)
Grounded in the shipped code (`CreateModel.swift`, `Tokens.swift`, `ResumeCard.swift`). What changes:
1. **First launch (6a):** Gate gains `tuning(part, of)` — non-blocking screen counting the six `.mlmodelc` compiles as real units ("2 of 6 parts", checklist rows check as each lands; small arc inside a row, never a bar within a component). "Look around meanwhile" opens the app; ControlNet compiles here so first Enhance never pays foreground. Create button renders the tuning readout while cold; a Create tap during tuning queues an explicit start ("Starts when tuning finishes"), cancellable the moment it begins.
2. **Long wake (6b):** `preparing` keeps the arc but names each landing component in the capsule ("Text encoder ready · 9%" → "Image model ready · 78%"), using the existing bytes-weighted `wakingFraction` events. No % before the first component. Same-object crossfade into "Step 1 of 28".
3. **Enhance (6c):** home is the picture — Enhance pill beside Save (shown only when the model declares a ControlNet, cost caption "about a minute"); while running, a 3×3 veil over the framed picture clears tile-by-tile in place, capsule reads "Adding detail… tile 4 of 9". Create disabled throughout (35% ink segment; tap → toast "One thing at a time…"). Identical from Create result and Gallery detail. Failure card copy adds "Your wallpaper is untouched."
4. **About (6d):** ⋯ circle in Gallery header → About sheet: app/version, Model line, Acknowledgements row + licence credit on the sheet's face (CreativeML Open RAIL‑M), Advanced doorway, "Your wallpaper folder → Open in Files". Not a third screen.
5. **Resume (6e):** card → one-line chip docked above the segment control ("Unfinished — enhancing, 2 of 9 tiles · Resume"); Discard behind long-press; tap chip to expand full card. Shelf priority: tuning > resume > toast. Never auto-resumes.
State-machine summary and constraint flags are on the board at 6f. Constraint check: all indicators count real completed units; no time estimates; morph object unbroken; nothing opaque over the picture.

## About the Design Files
The files in this bundle are **design references created in HTML** — prototypes showing intended look and behavior, not production code to copy. The task is to **recreate these designs in SwiftUI** using the current Liquid Glass API surface (`.glassEffect()`, `GlassEffectContainer`, `glassEffectID` + `@Namespace`, `.buttonStyle(.glass)`) — never `.ultraThinMaterial` or hand-rolled blurs. Open `AISixten Wallpapers Mockups.dc.html` in a browser to see everything on one pan/zoom board (turns are stacked newest-first; each mock has an id badge like `2a`).

**Canonical design = white glass (turns 2–4).** Turn 1 (dark glass) is archive/reference only, except: 1b (morph spec), 1c gallery layouts, 1d iPad, 1f tokens, 1h reduced-modes — whose layouts/annotations still apply, re-skinned in white glass.

## Fidelity
**High-fidelity.** Colors, type sizes, spacing, radii, and copy are final. Recreate pixel-perfectly with SwiftUI equivalents (SF Pro = system font; the HTML's px values map 1:1 to pt).

## App structure
- `RootView`: if model not installed → FirstRunGate; else TabView-less two-screen shell with a floating glass segment control (Create · Gallery) — one `GlassEffectContainer`.
- No third screen. The first-run gate never reappears once the model is installed.

## Screens / Views

### 1. First-run gate (board id 4a — four states)
**Consent** — headline "Everything happens on your iPhone" (30pt/700), body 16pt at 60% ink. Glass card (r28) listing: "Image model — 2.6 GB", separator, "Download over Wi‑Fi only" toggle (default ON, `#34C759`), footnote 12.5pt/50%: "Hosted by Apple, downloaded once. It never phones home — the app has no network access after this." Primary capsule 56pt: "Download · 2.6 GB". Caption below: "You can keep using your phone — it continues in the background." **No skip exists.**
**Downloading** — headline "Getting the model", body gives honest ETA + permission to leave. Card: name + `1.1 of 2.6 GB` (tabular numerals), 10pt progress bar `#0A84FF` on 8% ink track, `Wi‑Fi · 4.6 MB/s`, Pause chip. Progress is real bytes from `BADownloadManager` — never simulated.
**Interrupted (paused, waiting for Wi‑Fi)** — bar desaturates to 25% ink (state also carried by words, never color alone), bytes preserved, two actions: "Use cellular this once" (primary, scoped override) / "Keep waiting".
**Ready** — green check `#1F9D47`, "Ready", "The model lives on your iPhone now. You won't see this screen again." Primary: "Make your first wallpaper" → Create; secondary glass pill: Surprise me.
Implementation: model ships as an **Essential asset pack via Apple-Hosted Background Assets** (200 GB per-app allowance; `BAEssentialDownloadAllowance` / `BAEssentialMaxInstallSize` set to real sizes).

### 2. Create (2a white glass; states per 1a)
Layout (iPhone 402×874 ref): title "Create" 28pt/700 centered at y≈96; prompt field = glass card r28, min-height 148, padding 20/22, text 19pt (placeholder 45% ink "Describe a wallpaper…"); Surprise-me glass pill (44pt) centered under the field; Create capsule 56pt above the tab capsule; tab capsule bottom-center (segments 15pt/590, active segment 8% ink plate).
- **Empty**: Create disabled = lighter fill (`rgba(255,255,255,.45)`), label 35% ink. Ambient bg = most recent wallpaper heavily blurred+dimmed; first launch = pale dawn gradient `#FDFCFA→#EFECE5→#E2DED4` (radial, from top).
- **Typed**: keyboard up; Surprise-me shrinks to 38pt pill left; Create (tinted) rises beside it, above keyboard. Surprise me **fills the field visibly** (teaches prompting; re-tap re-rolls); it never generates directly.
- **Generating**: prompt echoes at top (14pt/50%); centered 300×540 r32 frame shows the forming image — intermediate latents decoded every 2–3 steps under a **milk veil**: white overlay `rgba(255,255,255,.22)` + blur easing 26→0pt. Progress capsule 300×56: fill = real step fraction (`rgba(10,132,255,.3)` on white glass), label "Step N of M" 15pt/590, embedded 44pt cancel circle.
- **Complete** (board id 5b): image full-bleed. **Every terminal state must have a live exit** — the original dead end (finish → only Save/share/regenerate) is a bug. Three exits: back circle top-left → Create empty; the Create segment control (never inert); and the prompt itself. Bottom: prompt plate r999 with a pencil glyph, the quoted prompt, and a **Tweak** chip (renamed from "Use again", promoted — re-rolling one word is the primary loop). Action row: "Save for Wallpaper" tinted capsule (flex) + share + regenerate 52pt circles. Save is an action, not the only door. Tiny plate caption "Saved to your iCloud folder".
- **Edit over image** (board id 5b): tapping Tweak/prompt returns the prompt field **over the finished picture**, which is held behind a light scrim (`rgba(255,255,255,.28)` + 8pt blur) so the user keeps their reference while changing a word. Primary button reads **Regenerate** (not Create) — you're iterating on this image. This makes "change one word and try again" the path of least resistance. On iPad/Mac the field never left (it's the toolbar), so Tweak just refocuses it and swaps Create→Regenerate; the picture stays in the featured tile. The seam is iPhone-only.
- **Failed** (1a, re-skin white): glass card r32 — "That one didn't come together" 21pt/650, reason in plain words, "Nothing was lost — your prompt is still here." Buttons: Try again (tinted) / Edit prompt.
- **Cancelled**: return to typed state; toast pill "Stopped — your prompt is kept", fades after 2 s.

### 2b. Waking the model (board id 5a) — unmeasurable wait
When generation starts but the model isn't resident (cold start, measured up to ~8 s; Core ML reports nothing between "loading" and "loaded"), the frame is empty white glass with a slow indeterminate arc (breathing conic ring, NOT a jittery spinner). Capsule label: "Waking the model…". **No fake fraction.** If it runs past ~3 s, a single quiet line fades in below the arc: "First wallpaper of the session takes a moment — the model is loading into memory. The next ones are instant." Cancel fades into the capsule. It is the **same glass object** (`glassEffectID("job")`) that becomes the progress capsule — when the model loads, the arc dissolves and the label crossfades (0.2 s) to "Step 1 of 28" with the fill track appearing from 0; no resize, no reposition. Must read calm at both 400 ms and 8 s. Pair with `ImageGenerator.prepare()`/`isReady` and CreateModel's `.preparing` phase; Create should preload on appear so the wait usually finishes while the user types.

### 3. The morph (1b) — one glass object, `glassEffectID("job")`
Create capsule → widens into progress capsule (0→0.45 s, spring response 0.8 / damping 0.85; tint drains to neutral, cancel appears inside) → at ~step 5 the capsule **grows into the picture frame** as the first latent decodes → final step: frame expands full-bleed (0.5 s spring) and the capsule morphs once more into "Save for Wallpaper". Cancel plays it in reverse. Failure: capsule stops, drains tint, morphs into the failure card. All in one `GlassEffectContainer`.

### 4. Gallery (1c layouts, white glass)
- **Empty**: teaches — ghost tile (88×156 glass, r20), "Nothing here yet" 20pt/650, "Wallpapers you make will gather here — created on this phone, kept in your iCloud.", tinted Surprise-me pill → jumps to Create pre-filled.
- **Grid**: title "Gallery" 28pt/700 left + caption "12 wallpapers · in your iCloud folder" 13pt/45%; 2-col grid, tiles aspect 9:19.5, r22, 12pt gap, newest first. No per-tile metadata.
- **Single image**: full-bleed; 44pt glass back circle top-left; prompt plate r22 (quoted prompt 14pt + "Use again" chip → Create pre-filled); action row: "Save for Wallpaper" tinted capsule + share + delete (52pt circles; delete glyph `#C83636`, never primary).
- **iOS handoff sheet** (mandatory honesty): white-glass sheet r38 over 12% white scrim — green check `#1F9D47` + "Saved to Photos" 20pt/650; "iPhone doesn't let apps change the wallpaper — that last step is yours, and it takes about ten seconds:"; numbered steps 1 Settings → Wallpaper, 2 Add New Wallpaper → Photos, 3 "It's the most recent picture — tap it"; button "Open Settings" (deep-link as far as allowed). **Never claim the wallpaper was set.**

### 5. iPad (1d)
Landscape: Create collapses into a toolbar over the gallery (prompt field 420pt + Surprise me + tinted Create); 4-col grid, featured 2×2 newest tile; new generations form in place in the grid (same veil treatment). Quiet aspect chip bottom-right: iPad 4:3 (default) / Phone / Wide.

### 6. Mac (3a)
Single window (ref 1140×700, warm paper bg `#F7F5F0→#E9E6DF`): create toolbar (prompt, Surprise me, Size picker "This display · 5120×2880", Create); 3-col grid of 16:10 tiles, selected tile ring `#0A84FF`. Context menu (white glass, r20): **Set as Desktop** (tinted row — calls `NSWorkspace.setDesktopImageURL`, finishes immediately) · This display ✓ · All displays · Every Space on this display · — · Share… · Delete. Default size = frontmost display resolution.

## Interactions & Behavior
- Springs: response 0.8, damping 0.85 (morphs); toasts fade 2 s; sheet presentation standard.
- **Reduce Motion**: geometry morphs → 0.2 s opacity crossfades at final positions; progress fill animates width only; veil lifts in 3 discrete steps; no spring overshoot anywhere. Emerging-image preview is kept (content change, not motion).
- **Reduce Transparency**: every glass fill → opaque token (`#F2F0EB` light / `#2C2E38` dark); blur, saturation, inner highlight removed; hairlines stay; layout identical.
- Progress (download and diffusion) is always real. No fake bars, no spinners.

## State Management
- `ModelStore`: notInstalled / downloading(bytes, rate) / paused(reason) / installed — from BADownloadManager delegate.
- `GenerationJob`: idle / preparing(waking) / running(step, total, latentPreview) / done(image) / failed(reason) / cancelled / editing(over done image). Prompt string survives failure/cancel/done. `preparing` and `running` share one glass object; `done` and `editing` share the picture layer (editing adds the scrim + field).
- Diffusion: measured ~1.6 steps/sec on-device; a full generation is ~15–30 s. **Open decision:** 28 steps ≈ 17.5 s at that rate — confirm on-device full-generation time to decide whether 28 holds or drops to ~20. Do NOT design around the current square-crop output (a conversion limit being fixed separately).
- Test note: reachability tests assert `.done` is reached but not that it can be left. Add assertions that every terminal state exposes a live exit.
- `Gallery`: images + stored prompt each, from the app's iCloud Drive ubiquity container (visible in Files). Aspect implied by platform; user override only on iPad/Mac.

## Design Tokens
- Accent `#0A84FF` (tinted glass at 75% opacity on light; white label). Success `#1F9D47` (light plates) / `#4CD964` (dark). Destructive `#C83636` (light) / `#FF7878` (dark) — never the only signal.
- Ink `#1A1A1E`; ink-2 = 55–65%; ink-3 = 45%. Dark theme ink = white at 100/65/45%.
- Light bg `#F4F2EE→#E9E6DF`; dawn gradient `#FDFCFA→#EFECE5→#E2DED4`; dark bg `#171A26→#0D0F16`.
- **White glass recipe** (reference for the HTML only — in SwiftUI use `.glassEffect()`): blur 24, saturation 160%, fill `rgba(255,255,255,.55)` (.6 for menus/sheets .62–.68), hairline 0.5pt `rgba(255,255,255,.8–.95)`, inset top highlight, drop shadow only over light backdrops.
- Radii (concentric): screen 48 → sheet 38 → card/frame 28–32 → plate 22 → tile 20–22 → capsule 999. Spacing: 4/8/12/16/24/32; screen margins 24.
- Type (SF Pro, Dynamic Type): 34 Large Title (iPad/Mac) · 28/700 screen title · 30/700 gate headline · 21/650 card heading · 19 prompt text · 17/620 buttons · 15 secondary · 13 caption · tabular numerals for all counts.
- Hit targets ≥ 44pt. VoiceOver: generated images use their stored prompt as accessibility label.

## Assets
No bitmap assets. All icons are SF Symbols equivalents: sparkles (Surprise me), square.and.arrow.up (share), arrow.clockwise (regenerate), trash, xmark (cancel), chevron.backward, checkmark.circle. Gray tiles in the HTML are drag-drop image slots — stand-ins for generated wallpapers.

## Files
- `AISixten Wallpapers Mockups.dc.html` — the full board (open in a browser; requires the sibling files below)
- `ios-frame.jsx`, `macos-window.jsx` — device/window chrome used by the board (not part of the design)
- `image-slot.js` — placeholder-image component used by the board (not part of the design)
