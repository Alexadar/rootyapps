# AISixteen Architecture — design handoff
On-device AI interior & exterior redesign. iPhone · iPad · Mac. No account, no network, no subscription — identical in Airplane Mode.

Second app in the AISixteen family. Shares the wallpaper app's Liquid Glass system:
`.glassEffect()` · `GlassEffectContainer` · `glassEffectID` + `@Namespace` · `.buttonStyle(.glass)`.
**Never** `.ultraThinMaterial` / `.regularMaterial` / `.thinMaterial`.

## Scope decisions (current model reality)
- **No segmentation.** The diffusion model redesigns the whole frame, conditioned on depth. No region-picking UI anywhere; no copy implies per-object edits.
- **No measuring.** No dimension callouts, no metric claims. Depth conditioning = "walls, windows and proportions stay put" — that is the whole promise and the only geometry claim in copy.
- Direction = structured presets that **seed an editable prompt field** (presets are prompt macros; free text optional, never required).

## Tokens (derived — reconcile against the wallpaper bundle's 1f token sheet when available)
| Token | Value |
|---|---|
| Ink | #1D1A17 |
| Accent (this app only) | terracotta #B4552D — drains to neutral during generation |
| Canvas | #EFEBE4 / #F4F1EB |
| Glass | white .60–.72, blur 18–24 pt, saturate 1.7, border white .6–.7 |
| Radii | capsule 999 · card 26 · sheet top 34 · preset card 18 |
| Type | SF Pro, px = pt |
| Morph | spring response 0.8, damping 0.85 (cancel plays reverse) |
| Milk veil | white .22 over intermediates, blur 26 → 0 pt across steps |

## Screens & states
- **Capture** — live coach line (level / distance / light), Interior·Exterior glass segment, library import. `CaptureView.swift`
- **Direction** — photo header with depth badge + Retake (photo-check folded in), preset cards, prompt field, variation count, CTA priced in minutes. `DirectionView.swift`
- **Generating** — named stages (Reading the space → Composing → Refining → Full resolution), real step counts, forming image under the milk veil, scoped cancel, queue. Interruptions are **pauses, never errors**: phone call / thermal / low battery / background-suspended. `GeneratingView.swift`
- **Result** — wipe slider (recommended; tap-to-flip + hold-to-peek secondary). VoiceOver: one adjustable element. `ResultView.swift`
- **Library** — grouped by space; variations under each; iCloud app folder (user-owned storage language only). `LibraryView.swift`
- **Shell** — floating glass segment (Redesign · Library), one GlassEffectContainer, not a TabView. `RootView.swift`
- **Live Activity** — forming thumbnail, stage, step x/y, queue depth; suspended reads "Waiting for you", never fake progress. `RedesignActivity.swift`
- **Seam** — `ImageGenerator` protocol + step-based `GenerationProgress` (never a 0–1 float) + mock. `GenerationSeam.swift`

## Platform honesty
- Minutes of background Neural Engine work is **not guaranteed**; iOS may suspend. Checkpoint denoising state; resume on foreground; completion via local notification.
- Thermal throttling is observed (`ProcessInfo.thermalState`), never predicted. Time-left is a rolling estimate from measured step duration.
- Mac: no Live Activity — standard notification; sidebar shell; no "Set as Desktop" here.

## Accessibility floor
Dynamic Type to AX5 (grids reflow to one column), VoiceOver on every control and the comparison, hit targets ≥ 44 pt, Reduce Transparency → opaque #F6F3ED with hairline borders (layout identical), Reduce Motion → morph becomes cross-fade, intermediates as stepped stills.

## Files
Swift files are **compilable SwiftUI mockups** of the designs (static state, mock generator) — a starting point, not production code. HTML board: `AISixteen Architecture Mockups.dc.html` (open in a browser; drag the Result handle).
