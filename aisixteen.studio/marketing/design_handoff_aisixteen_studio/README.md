# AISixteen Studio — design handoff

On-device AI photo enhancement. iPhone · iPad · Mac. Same family and white-glass Liquid Glass system as AISixteen Wallpapers — **reuse the system, not the screens**.

Open **`AISixteen Studio Mockups.html`** in a browser: one pan/zoom board, each mock badged (`1a`…`1m`). HTML px map 1:1 to pt. SF Pro = system font. All values below are final unless re-skinned against the wallpaper bundle tokens.

## The mental model — editor, not generator

The user's photo is the subject. No prompt field anywhere. The primary verb is **Enhance**, the primary dial is **Strength**, and the original is one gesture away at every moment.

- **The original is sacred.** Original file is read-only, never rewritten. Edit = recipe (masks + strengths + seed) → enhanced copy, the only file ever written. Fully revertible forever.
- **Conservative default.** Strength = 35 ("Subtle").
- **Selective application.** Whole photo / Subject / Background / Brush.
- **Comparison is constant** — available in every state including during the pass.

## Screens (board ids)

| id | Screen |
|---|---|
| 1a | Import — iPhone, empty state, Library/Camera, privacy line, Enhance·Library glass segment shell |
| 1b | Edit — photo loaded, scope segment + strength slider + Enhance capsule in one floating glass panel |
| 1c | Applying — step progress capsule with Cancel, milk veil, live original/enhancing split |
| 1d | Result — split handle, hold-for-original, strength as live blend, Revert + Save |
| 1e | Export sheet — Save as new (default) / Replace in Photos / Share, literal fate-of-the-original copy |
| 1f | Library — iCloud folder, paired before-swatch tiles, download-on-demand state |
| 1g | iPad — controls as floating right column, segment shell top-center, Pencil → Brush |
| 1h | Mac — sidebar library, glass toolbar, drag-and-drop import, Space = hold original, ⌘Z = revert |
| 1i | Spec — strength detents + selection model |
| 1j | Spec — comparison gestures, VoiceOver, original-protection pipeline |
| 1k | Reduce Transparency / Reduce Motion variants |
| 1l | App icon |
| 1m | System deltas from Wallpapers + Architecture distinctness test |

## Strength — one dial, named detents

0–100 rail, detents at **Whisper 15** (noise/micro-contrast, pixel-faithful) · **Subtle 35 — default** · **Balanced 55** (reconstructs fine detail) · **Strong 80** (full re-render, inline warning "may alter fine details"). After the pass the dial is a **live blend** — 0 is the original bit-for-bit; no re-run to back off. Each scope holds its own strength; scopes compose into one recipe: `original + (mask × strength × pass)`.

## Comparison — three ways, always

1. **Press-and-hold** anywhere shows the original (Mac: hold Space). Release snaps back.
2. **Split handle** — persistent, draggable edge to edge, present during Applying.
3. **Strength → 0.**

**VoiceOver:** the handle is one adjustable element — "Comparison. Showing enhanced. Adjustable." Swipe up/down = 10% steps, announcing "70 percent enhanced." Double-tap-and-hold speaks "Showing original" while held. Strength slider announces detent names, not bare numbers. Hit targets ≥44pt; handle grip 38pt visual on a 56pt target.

## Applying — design the wait honestly

Tens of seconds, single pass. Progress is **steps, not a percentage** ("Enhancing · step 9 of 20"). The image resolves live under the **milk veil** (white `rgba(255,255,255,.22)`, blur 26→0pt) against the original split. Cancel is always present, plays the morph in reverse, photo returns untouched.

**The capsule morph (same object, same spec as Wallpapers, spring response 0.8 / damping 0.85, one `glassEffectID` in one `GlassEffectContainer`):** Enhance capsule → widens into progress capsule (tint drains to neutral, Cancel appears inside) → morphs into **Save…** on completion. Failure stops the capsule, drains tint, morphs into the failure card.

## Export — say what happens to the original

- **Save as new photo (default):** "The enhanced copy lands next to your original in Photos. Nothing is overwritten."
- **Replace in Photos:** "Photos keeps the original inside the edit — you can revert there anytime."
- **Share…**
- Footer: "Enhanced on this iPhone. Never uploaded."

No watermark, no upsell, no Pro badge.

## Library

App's iCloud ubiquity folder, user-visible in Files/Finder. Tile = enhanced image + **original corner swatch** (34pt, 1.5pt white border) + strength/scope badge. Download-on-demand state for files synced from another device. iCloud is the user's own storage — nothing may read as an account or a service.

## Tokens (deltas from Wallpapers)

- Glass panel: `rgba(255,255,255,.60)` + `blur(26px) saturate(1.45)`, border `rgba(255,255,255,.78)`, radius 28 (panels) / 999 (capsules), shadow `0 14px 40px rgba(20,20,25,.22)` + inset top highlight.
- Ink `#1A1A1A`; secondary ink at 55%; canvas `#F4F3F0`.
- **New accent:** `oklch(52% 0.09 245)` (steel blue) — Enhance/Save capsules, strength fill, selected mask overlay. Darkens to `oklch(45% 0.10 245)` under Reduce Transparency for 4.5:1.
- New components: comparison split handle · scope segment · strength slider with detents · paired-swatch library tile · fate-of-the-original save sheet.
- Absent by design: prompt field, aspect-ratio picker.
- No `.ultraThinMaterial` / `.regularMaterial` / `.thinMaterial` anywhere. Current Liquid Glass APIs only.

## Accessibility variants (1k)

- **Reduce Transparency:** panels opaque `#F7F6F4` + 1px hairline, blur off, accent one step darker.
- **Reduce Motion:** morph → cross-fade; veil opacity steps instead of animated blur; hold-original swaps instantly; split handle unchanged (direct manipulation).

## Not the Architecture app

Studio's grammar is photographic: strength, masks, subject/background, a split you drag — a continuous blend of **one** image. Architecture's is spatial: geometry, dimensions, A/B proposals between two futures. Studio never shows a floor plan, a measurement, or a proposal pair. Verb test: Studio **enhances** (degree); Architecture **reimagines** (kind). Any screen that would fit both apps fails review.

## Constraints

No account, no network, no ads, no subscription, no credits, no trial. Behaves identically in Airplane Mode.
