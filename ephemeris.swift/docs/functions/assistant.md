# Explain this screen — on-device Q&A

**Status:** **shipped** — glossary, screen contexts, App Entities, and a single-turn Q&A sheet.
Off by default; a Settings toggle adds a ✨ toolbar button
**Lives in:** `EphemerisKit/Sources/EphemerisKit/Assistant/` (Glossary · ScreenContext ·
ContextRanking — all pure) and `ephemeris/Assistant/` (Entities · ScreenContexts · AssistantEngine ·
AssistantSheet)
**Tests:** `ScreenContextTests.swift` (12) · `AssistantChecks.swift` (5 UI)
**Gate:** 0 — it explains whatever screen you are on, including a brand-new install
**Depends on:** every other function, since it describes them

## What it does

Answers one question about the screen the user is looking at, on device, using Apple Intelligence.
Two audiences, one answer: someone who has never opened an astrology app and asks *"what is this?"*,
and a practitioner asking why a placement scored as it did.

**Single turn by construction.** A fresh `LanguageModelSession` per question, no transcript. That is
the requested shape and also the only workable one: the on-device context window is **4,096 tokens
shared between prompt and response**, so a conversation would spend its budget remembering itself.

## The three layers a model needs

1. **Where we are** — screen, moment, place, zodiac, and the user's gate. Without it the same
   numbers could be today's sky, a birth chart, or a projection.
2. **What the terms mean** — `Glossary`, ~50 entries transcribed from `docs/functions/*.md`.
   ⚠️ An `AppEntity`'s `@Property(title:)` is a **label, not a meaning**. Told only that a column is
   called "Dignity", a model invents a definition — which, beside an engine oracle-tested to
   arcminutes, is the worst available outcome.
3. **The data** — ranked and truncated.

## Truncation: ranked, measured, disclosed

**Four rows plus the counts**, everywhere, even where more would fit — so the truncation path is the
normal path and stays exercised rather than breaking unnoticed on the one screen with 104 rows.

- **Ranked, never the first N.** Nearest to now · tightest orb · nearest the observer · the current
  hour and its neighbours. The timeline opens thirty days in the past: head-truncation would hand
  the model a month of history and drop today.
- **Measured** with `SystemLanguageModel.tokenCount(for:)` where available (**iOS 26.4+**; this app
  deploys to 26.0), falling back to a deliberately pessimistic 2.5 characters per token. The usual
  four-per-token rule is calibrated on English prose, and this app's glyph-dense text tokenizes far
  worse — an optimistic estimate would say "fits" and then fail with `exceededContextWindowSize`.
- **Disclosed.** *"4 of 104, chosen by nearest to now"* goes to the model **and** to the user. Same
  honesty rule as polar absence, the void-of-course body set, and the export count.

## What it will not do

⚠️ **Explains; never computes.** Every number it may state is one the app handed it. The
instructions say so, the sheet says so, and the model is told to answer only from the supplied
context. It does not predict, does not give life advice, and does not calculate a position.

## Availability

`SystemLanguageModel` needs **A17 Pro or M-series**: iPhone 15 Pro and newer, M-series iPads, Apple
Silicon Macs. Four designed states — device not eligible · Apple Intelligence off · model
downloading · **language unsupported** (`supportedLanguages`, which matters for a 16-language app).

## Why the entities exist now

They are the substrate for Siri, not decoration. WWDC26 deprecated SiriKit, made App Intents the
replacement, and added **View Annotations** (`.appEntityIdentifier`) mapping SwiftUI views to
entities. Apple solved on-screen awareness *for Siri*; there is still no API handing an app's own
`LanguageModelSession` the screen, which is why `ScreenContext` exists. Modelling the content as
entities today makes the Siri pass wiring rather than a rewrite.

## Failure modes

- A screen with no context provider — the assistant shrugs on exactly the page that confused someone
- A term named with no glossary meaning, so the model invents one
- Head truncation, which drops the row the user is pointing at
- Silent truncation, which turns a partial answer into a confident wrong one
- Claiming a rising sign for an untimed chart, where the angles are undefined

## Related

Every function file — this one describes them all.
