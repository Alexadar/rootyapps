# Par — SwiftUI templates

Generated from the approved design (turn 3 on the design canvas: **amber on graphite, dark only**).
Drop these into `par/Par/` — they replace the minimal build-verified UI in place. Do **not** add a
parallel `DesignSystem/` folder to `project.yml`; these files live under `Par/Views/` so the types
do not double-declare.

## What is here

    Par/
      ParApp.swift                      DocumentGroup scene, ⌘-key commands
      Models/
        TapeRow.swift                   a tape line = inputs only, plus the damaged-line case
        TapeDocument.swift              FileDocument; each row decodes independently
      ViewModels/
        TVMViewModel.swift              @MainActor ObservableObject, computed outputs
        AmortizationViewModel.swift
        CashFlowViewModel.swift
        BondViewModel.swift
      Views/
        RootView.swift                  adaptive shell: split view / compact + pull-up tape
        TVMScreen.swift                 five registers, one hero
        TapeView.swift                  the tape as a list of solved problems
        TapeRowView.swift               one row, editable in place
        FailureNotice.swift             no-solution, multiple IRR, damaged line
        DesignSystem/
          Theme.swift                   Par.Palette, Par.Metrics, .glassCard()
          Fmt.swift                     every displayed number goes through here
          NumberField.swift             NumberField(range:) — bounded input
          ResultRow.swift               ResultRow(unit:emphasis:)
          HeroResult.swift              the one loud number
          SubScreenPicker.swift         segmented picker (amber ring = selected)
          ProvenanceStrip.swift         authority + conventions, per screen
          Keypad.swift                  Par's own 4-col / 3-col keypad

## The rules these files encode

- **Zero math in views.** View models hold `@Published` inputs and expose *computed* outputs that
  call the Kit. No view performs a division, not even to show a percentage.
- **Every numeric input has an explicit `min…max`.** `NumberField` requires `range:` and clamps on
  commit, so the Kit never receives an illegal domain.
- **Solves that can fail, fail visibly.** `TVMViewModel.Outcome` and `CashFlowViewModel.IRRPresentation`
  model the failures; `FailureNotice` / `MultipleIRRNotice` render them in the hero's place. No
  fabricated fallback number anywhere.
- **Units and conventions are always on screen.** `ProvenanceStrip` is furniture on every screen.
- **No pinned point sizes.** Everything is a Dynamic Type text style, including the hero
  (`.largeTitle`, wraps rather than truncates). Previews include an AX5 case.
- **`accessibilityIdentifier` on every input, every hero output and every tape row** (and on the tape
  row's result field specifically), ready for the later UI-test phase.
- **VoiceOver reads meaning, not glyphs** — see `Fmt.spokenMoney`: "present value, 420,000 dollars".
- **Dark only.** Amber is spent only on interaction; sign is carried by the minus glyph, weight and
  the spelled-out direction, never by hue.

## Seams to confirm before the first build

These call real, frozen Kit APIs, but a few initialiser labels were read from the public surface
rather than exercised. Confirm against the Kit source, and change the call site only — never the Kit:

- `Amortization.Loan(principal:periodicRate:periods:timing:rounding:balloon:)` — `AmortizationViewModel`
- `Bond.Terms(couponPct:fullPeriods:daysToNextCoupon:daysInPeriod:firstPeriod:fractionalPortionDays:fractionalPortionPeriodDays:)`
  and `Bond.yieldToMaturity(_:price:)` — `BondViewModel`
- `Amortization.Rounding.cents` spelling
- `DayCount.Convention.actualActual` case name

Verified as used: `TVM.Registers`, `TVM.solve(for:_:)`, `TVM.Variable`, `TVM.SolveError`,
`CashFlow.expand/npv/nfv/irr/mirr/payback/discountedPayback`, `CashFlow.Group`,
`Amortization.payment/schedule/balance/totals/totalInterest`, `Bond.accruedInterest/currentYield/`
`macaulayDuration/modifiedDuration/convexity`.

## Not yet written

Screens for Rate & APR, Depreciation, Dates & Day Count, Percent & Margin, Statistics and Real Estate.
Each is the same recipe: a `@MainActor ObservableObject` with bounded `@Published` inputs and computed
Kit outputs, plus a screen made of `NumberField` / `ResultRow` / `HeroResult` / `ProvenanceStrip`.
`RootView` already routes to them.

## Verification

`xcodegen generate` → `xcodebuild` for iOS **and** macOS → authored `#Preview`s. No simulator run,
no screenshots, no UI tests.
