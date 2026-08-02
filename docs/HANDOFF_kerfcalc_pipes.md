# HANDOFF — add **Pipe Layout** to KerfCalc (Kit first, then tools)

> Paste into a Claude Code session with working directory = `rootyapps` repo root.
> Target app: **`kerfcalc.swift/`** (shipped, live on the App Store at $9.99, `oleksandr.aisixteen.kerfcalc`).

---

## 0. Why we're doing this

KerfCalc is a buy-once, offline, no-ads, no-subscription construction calculator whose moat is
**validated math** — every displayed number is a call into an oracle-tested `*Kit`, never math in a view.

A demand scan on 2026-07-26 (`docs/n3_v4_candidates_2026-07-26.md`) found the pipe-trades niche wounded
in exactly the way our positioning answers:

- `Pipe Trades Pro Calc` (Calculated Industries) — 4,197 ratings, **free + subscription**, and **16 of its
  50 most-recent reviews** are subscription complaints (1★ 2026-05-11: _"Why is it a subscription?"_).
- Paid-upfront rivals in the adjacent bending space already sell at **$6.99–$7.99** with thousands of
  ratings — the price model is proven in this trade.

We already own the two things this needs: **`DimensionKit`** (feet-inch fraction arithmetic — the app's
whole wedge) and **`GeometryKit`** (trig). Pipe layout is the same triangle expressed in the trade's
vocabulary, so it lands as a new section in a listing that already exists rather than a new cold start.

## 1. Scope — and the hard boundary

**Build: pipe *layout geometry* only.**

✅ In scope — pure geometry on user-supplied numbers:
- **Simple offset** — given set (offset) and fitting angle → travel, run; and the inverse (angle from
  run and set).
- **Rolling offset** — given roll and set → true offset `√(roll² + set²)`, travel, run, and the required
  fitting angle.
- **Fitting multipliers & constants** — travel = set × (1/sin θ), run = set × cot θ, for the standard
  fittings (45°, 60°, 30°, 22½°, 11¼°) **and any arbitrary angle**.
- **Cut length** — centre-to-centre minus the two **user-entered** take-outs → end-to-end.
- **Parallel / multi-pipe offsets** — equal-spread runs, spacing preserved through the offset.
- **Percent grade / slope on a run** — fall over a horizontal distance (drainage), % ↔ ratio ↔ degrees.
- **Pipe weight** from OD, wall thickness, length and material density (formula, user-entered density).

❌ **Out of scope — do not build, do not suggest:**
- **Nothing electrical.** No conduit bending, no EMT, no NEC-derived anything. This is a deliberate
  product decision, already made — do not reopen it.
- **No pressure, flow, sizing, friction loss, venting, or fixture-unit work.** A wrong number there is
  silent and consequential; layout geometry is self-revealing (the pipe doesn't fit, you re-cut).
- **No embedded fitting/manufacturer tables.** Take-outs vary by manufacturer and standard — the user
  enters theirs, or picks from values they've saved. Never ship a transcribed ASME/manufacturer table.
- No copyrighted handbook tables of any kind. Formulas are free; tables are not.

## 2. The oracle story (this is the good part — make it explicit)

The pipe trades' famous "constants" **are** trigonometric identities, and that's a clean, provable oracle:

| Fitting | Published travel multiplier | Identity |
|---|---|---|
| 45° | 1.414 | `1/sin 45° = 1.41421356…` |
| 60° | 1.155 | `1/sin 60° = 1.15470054…` |
| 30° | 2.000 | `1/sin 30° = 2` (exact) |
| 22½° | 2.613 | `1/sin 22.5° = 2.61312593…` |
| 11¼° | 5.126 | `1/sin 11.25° = 5.12583089…` |

Assert that our computation reproduces the **published trade-table values** to their stated precision,
and that those published values equal the closed form — that is an *identity* oracle plus a
*reference* oracle, both cited. Do the same for run multipliers (`cot θ`: 45° → 1.000, 22½° → 2.414,
11¼° → 5.027) and for the rolling-offset composition.

Also assert the invariants the trade actually breaks on: right-triangle closure (`run² + set² = travel²`
at 45°), rolling offset reducing to simple offset when roll = 0, angle/travel round-trips, monotonicity
as the angle narrows, degenerate guards (zero set, angle ≤ 0 or ≥ 90°), and — critically — that
everything survives **feet-inch-fraction input and output** without drift (this is where `DimensionKit`
must be exercised, not bypassed).

Follow `calculators/VALIDATION.md` exactly: an `Oracles.swift` corpus where every expected number
carries a non-empty cited `source`, the integrity-guard suite, reference tests pulling values via
`Oracles.require(id)`, and Style-A headers labelling each suite *oracle-backed | identity | invariant*.
If you cannot cite a source for a number, mark it `TODO(oracle):` — do not invent one.

## 3. How to build it

**Phase 1 — the Kit. Stop after this and report.**
- New package `kerfcalc.swift/Kits/Pipe/PipeKit/` following the shape of the existing Kits
  (`Kits/Framing/FramingKit` is the closest model): swift-tools 5.9, `platforms: [.macOS(.v13),
  .iOS(.v16)]`, one target + one test target, **Foundation only, no dependencies, no resources**.
- `public enum PipeLayout` static namespace; unit-suffixed labels (`setInch`, `angleDeg`, `rollInch`);
  `precondition` on illegal domains only — **never clamp for UI**; `///` docs on every public symbol,
  with `Pure, stateless.` and a `MODEL CAVEAT:` where a convention is assumed.
- `swift test` green in `PipeKit`, offline.
- **Report and wait for human ✅ before touching the app target.**

**Phase 2 — the tools (only after approval).**
- Add a **Pipe** section to the existing catalog with tools: Simple Offset · Rolling Offset · Cut
  Length · Parallel Offset · Grade/Fall · Pipe Weight.
- Reuse the shipped design system exactly — `NumberField(range:)` with **min…max on every input**,
  `ResultRow(unit:emphasis:)`, `.glassCard()`, `SubScreenPicker`, `Fmt`. **Zero math in views**: a
  `@MainActor ObservableObject` view-model whose outputs are computed `PipeKit` calls.
- Feet-inch input must work everywhere the rest of the app accepts it.
- `accessibilityIdentifier` on every input and emphasised result; extend the ValueChecks UITest with
  the new tools' default-state values.
- Verify: `xcodegen generate`, then `xcodebuild` **iOS and macOS** → BUILD SUCCEEDED, UITests pass.

## 4. Repo rules that bite

- **No `.swift` in any product-facing name** (Guideline 5.2.5 — the shipped binary/menu-bar name must
  never read `kerfcalc.swift`). Directory names are legacy; `PRODUCT_NAME` is what matters. Kit names
  (`PipeKit`) are fine.
- **Version bump:** when this eventually ships, bump the **patch of `MARKETING_VERSION`** (1.0.0 → 1.0.1),
  not the build number.
- **No commit, no App Store Connect, no upload, no metadata change without explicit human go.** ASO
  (adding *pipe / offset / rolling offset / fitter* to the keyword field) is a separate, human-approved
  step after the tools land.

## 5. Report back with

Per phase: what you built, the oracle IDs and their cited sources, `swift test` result, any remaining
`TODO(oracle):`, and the iOS/macOS build results in Phase 2. Be explicit about anything you could not
cite — a green suite with an uncited number is worse than a red one.
