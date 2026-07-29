# Par — design brief

> **Paste this whole file into a fresh Claude Code session.** It is self-contained; assume no memory of
> prior chats. Working directory = the `rootyapps` repo root; the app lives in `par/`.
>
> **State as of 2026-07-28 — the app exists and builds.** `par/Par/` holds 37 files (~4,900 lines): a
> `DocumentGroup` app with all ten tools, each a `@MainActor` view model plus a screen built from the
> design system in `Par/Views/DesignSystem/`, rendered failure states, a `ProvenanceStrip` on every
> screen, and dark + AX5 previews throughout. iOS and macOS both build. So this brief is no longer a
> blank-page commission: it is the standard the existing screens should be judged against, and the
> visual language they should be raised to. Read `par/Par/Views/TVMScreen.swift` first — it is the
> reference the other nine follow.
>
> Your job is **the interface**. The mathematics is finished, validated against published authorities,
> and **frozen** — you will not touch it. Read `par/PLAN.md` §3 (licensing) and §5 (oracles) and
> `par/plan_tape.md` before you design anything, and treat both as constraints rather than context.
>
> **Verification is `xcodegen generate` + `xcodebuild` for iOS and macOS + authored `#Preview`s.** Do not
> boot a simulator, capture screenshots, or run UI tests. A human does the visual review.

---

## 1. What Par is, and who is buying it

An offline financial calculator for people who *must* have one: loan officers, mortgage and commercial
real-estate underwriters, treasury and fixed-income desks, and candidates studying for exams where only
a financial calculator is permitted. One-time purchase, no ads, no subscription, no in-app purchase, no
account, no network.

The moat is already built: every displayed number traces to a cited external authority — US Treasury
(31 CFR 356 App B), the CFPB's Regulation Z and Regulation DD, IRS Publication 946, NIST — and is
asserted by tests. **Your job is to make that trustworthiness legible.**

## 2. The wedge is layout. Read these two reviews twice.

Par's competitors do not fail at arithmetic. They fail at being apps. Verbatim, from the App Store:

> _"Calculator opens at about **twice the size of my iPad screen** making half the buttons inaccessible.
> No resize or scroll function available."_ — Vicinno Financial Calculator, 4.2★, 75 months stale

> _"I'd give it 5 if it had a **Split View** on the iPad. Asked but never got a response."_ — same app

> _"Does not support landscape mode… **There are better apps out there that show history** and support
> landscape."_ — BA Financial Calculator (PRO), 1★

That is the entire opening. Three consequences, and they are requirements, not polish:

1. **Adaptive layout that genuinely works** on iPhone, iPad (including Split View and Slide Over, at
   every column width), and Mac (including a resized-small window). Nothing fixed-width, nothing that
   assumes a full-screen iPad, nothing that clips a control off-screen.
2. **Dynamic Type everywhere, with no pinned point sizes** — including the hero result. A sibling app in
   this portfolio pinned its hero readout at 54 pt; do not inherit that. Test at the largest accessibility
   size, and let numbers wrap or scale rather than truncate.
3. **Landscape on iPhone must work**, because a competitor lost a customer over it.

## 3. The tape is a first-class surface, not a history drawer

`par/plan_tape.md` is the full brief with its dated review evidence; the summary you must design around:

**A financial calculator's unit of work is a solved problem, not a keystroke.** Given four of
`n · i · PV · PMT · FV`, solve the fifth. Professionals produce *sequences* of these — three refinance
scenarios, five bond comparisons — and need to see them side by side. Every incumbent throws that away,
and the one Par is displacing loses it *silently*:

> _"**Stored registers will 0 out for no reason whatsoever.** Stored number in register will be
> exponentially higher when you recall it, again, no reason whatsoever."_ — Vicinno, 1★, 2024-11-16

Ten of fifty recent reviews of the $9.99 category leader mention the tape, history or saving. It is what
that app is loved for:

> _"I love that you can easily turn sideways to quickly see the **'tape'** results of previous
> calculations."_ · _"**Love seeing a tape entry as I enter**."_ · _"It allows me to **go back and to fix
> a mistake** while I calculate — I don't have to redo the whole thing."_ · _"**I would give much to have
> a calculator from which I could print the tape.**"_

### What that means for the design

```
▸ TVM · "123 Oak St — 30yr"     n 360 · i 6.25% · PV 420,000 · FV 0   →  PMT   −2,586.34
▸ TVM · "123 Oak St — 15yr"     n 180 · i 5.75% · PV 420,000 · FV 0   →  PMT   −3,488.85
▸ Bond · "Treasury 2031"        price 98.75 · coupon 4.25 · …         →  YTM     4.443%
```

- **A list of rows, never a text blob.** Each row: optional label, inputs collapsed to one line, result
  as the emphasised number in its own column. Rows are independent solves — there is no running total,
  and cross-line arithmetic is explicitly out of scope.
- **Appending is automatic and silent.** No save button. The incumbent's failure was silent *loss*; Par's
  behaviour is silent *retention*.
- **A row is editable in place.** Tap it, change an input, it re-solves. Nothing else on the tape moves.
- **A free-text label per row.** This is what turns a tape into a client record; design for it being
  empty most of the time and long occasionally.
- **On iPad and Mac the tape sits beside the calculator** — that is the layout the incumbents fail at, and
  two of their fatal reviews are about exactly this. On iPhone it is a second surface (tab or pull-up),
  and it must be reachable without losing what is being typed.
- **Print and export are visible affordances**, not buried in a share sheet: system print for the tape,
  for an amortization schedule and for a cash-flow list, plus plain-text and CSV share. This is the single
  most explicit unmet ask in the category.
- **Tapes are documents** — named, listed, reopened (`DocumentGroup`). Nothing device-local, so an iCloud
  container can be switched on later without a migration. iCloud sync is deliberately **not** in v1; when
  it arrives the requirement is absolute (the same tape, complete and current, on all three platforms),
  so do not design anything that assumes a single device.

### What the tape must never do

Store a computed number it cannot re-derive. The document holds inputs; reopening re-runs the Kit and must
reproduce the stored result **exactly**. The Kits already guarantee the half of this that is theirs — every
input type round-trips losslessly, decoding validates and throws instead of trapping, and solves are
bit-for-bit deterministic (`ReplayTests.swift` in each Kit). Your side is: never cache a result you cannot
regenerate, and never let a decode failure crash — surface it as a damaged line the user can see and fix.

## 4. The maths you may call — and must not change

Ten Foundation-only Kits under `par/Kits/`, each a local SPM package already wired into `project.yml`.
**Their APIs and their oracle corpora are frozen.** If a design need appears to require new math, that is
a question for the human, not an edit.

| Kit | What it answers | The screen it implies |
|---|---|---|
| `TVMKit` | solve any of n · i% · PV · PMT · FV; payment/compounding frequencies; begin/end | the primary screen: five registers, one hero result |
| `AmortKit` | schedule rows, balance after k, year and range totals, balloon, cent-rounding | a real scrollable **table**, printable |
| `CashFlowKit` | NPV · NFV · IRR (unique/multiple/none) · MIRR · payback · discounted payback | grouped cash-flow **list** editor + results |
| `BondKit` | Treasury's five price cases, accrued interest, YTM, duration, convexity, bills, TIPS | price/yield pair with the settlement dates visible |
| `RateKit` | APR (Regulation Z actuarial + US Rule), APY / APY earned, nominal↔effective↔continuous | a rate-conversion screen and an APR screen |
| `DepKit` | straight line, declining balance, crossover, SYD, MACRS half-year and mid-quarter | method picker + year-by-year table |
| `DayCountKit` | 30/360 · 30E/360 · 30E/360 (ISDA) · Actual/Actual · Actual/360 · Actual/365F, date arithmetic | days-between-dates, and the convention picker other screens borrow |
| `PercentKit` | % change, markup vs margin, cost/sell/margin, break-even | small single-purpose forms |
| `StatKit` | 1-var and 2-var statistics, regression (linear/log/exp/power), forecast | data entry list + fitted line readout |
| `RealEstateKit` | NOI, cap rate, DSCR, LTV, max loan, cash-on-cash, GRM | an underwriting screen |

Rules that are not negotiable:

- **Zero math in views.** A `@MainActor ObservableObject` per screen holds `@Published` inputs and exposes
  *computed* outputs that call the Kit. Views format and display; they never calculate, not even a
  division to show a percentage.
- **Every numeric input has an explicit `min…max`.** The Kit guards illegal domains by trapping or
  throwing; the field's job is to make an illegal value un-enterable.
- **Solves that can fail, fail visibly.** `TVM.solve` throws (`noSignChange`, `termHasNoSolution`,
  `degenerate`), and `CashFlow.irr` can return `.multiple` or `.none`. Design for these: "this loan has
  two internal rates of return" is information the professional wants, and picking one silently is the
  behaviour Par exists to replace. Never render a fabricated fallback number.
- **Units and conventions are always on screen.** A rate says whether it is nominal or effective; a bond
  price says its day-count convention; a MACRS column says which table it came from. This is the product's
  whole claim, made visible.

## 5. What to port, and what not to invent

Do **not** invent a design system. Port the primitives from a shipped sibling — `truecourse.swift/DesignSystem`
or `overtonelab.swift` — into `par/Par/Views/`, replacing in place. Bring `NumberField(range:)`,
`ResultRow(unit:emphasis:)`, `.glassCard()`, `SubScreenPicker`, `Fmt`. Do not add a parallel
`DesignSystem/` folder to `project.yml`: the types double-declare and the build breaks.

Native components, no theming, no animation for its own sake. The aesthetic target is an instrument, not
an app: quiet surfaces, one loud number per screen.

## 6. Accessibility and identifiers

- An `accessibilityIdentifier` on every input, every hero output, and every tape row (and on the tape
  row's result field specifically) — a later phase adds UI tests and will need them.
- VoiceOver labels that read the *meaning*, not the glyph: "present value, 420,000 dollars", not "PV".
- Full keyboard navigation on Mac, and ⌘-key access to the surfaces.
- Contrast and hit targets: this app gets used on a job site and in a car, one-handed.

## 7. Hard bans

**Never**, anywhere — app name, subtitle, keyword field, description, screenshots, UI text, code
identifiers, or asset names: **HP · 12C · 12c · BA II Plus · BA-II · TI · Texas Instruments · 10bII ·
10BII**. These are live trademarks and a competitor trademark in App Store metadata is auto-rejected at
review.

**Never copy trade dress.** No gold-on-brown key grid, no borrowed key legends, no imitation of a physical
unit's faceplate. Par's layout must be recognisably its own — which is also the point, since the
incumbents' layouts are what people complain about.

No StoreKit, no paywall, no unlock gate, no analytics, no network calls.

## 8. Definition of done

- [ ] Screens for every Kit surface in §4, each with inputs bounded by `min…max` and one clear hero result.
- [ ] Amortization and cash flows render as real scrollable tables, and both print.
- [ ] The tape: automatic append, in-place edit of a single row, per-row label, document open/save, print,
      text and CSV export — beside the calculator on iPad and Mac, a second surface on iPhone.
- [ ] Adaptive at every width including iPad Split View, iPhone landscape and a small Mac window.
- [ ] Dynamic Type honoured throughout, no pinned point sizes, verified at the largest accessibility size.
- [ ] Failure states designed: no solution, multiple IRRs, damaged tape line.
- [ ] `accessibilityIdentifier` on every input, hero output and tape row.
- [ ] A light and a dark `#Preview` for every screen.
- [ ] `xcodegen generate` → iOS **and** macOS `xcodebuild` → BUILD SUCCEEDED.
- [ ] No simulator run, no screenshots, no UI tests, no ASC, nothing committed without explicit human go.

> **Note for whoever runs this brief:** §4's screen list is derived from the Kit APIs, which are final.
> The minimal build-verified UI from `PLAN.md` §6 is the starting point to replace, not a design to
> preserve — read it for the view-model seams, then design freely inside the constraints above.
