# Par — the tape · plan

> Companion to `par/PLAN.md`. Read that first — this file adds one feature and does not change §3
> (licensing), §5 (oracles) or the Kit APIs. **Every claim below is a dated App Store review, quoted
> verbatim, pulled from the iTunes Customer Reviews RSS on 2026-07-27.**

---

## 1. The problem

A financial calculator's real unit of work is not a keystroke — it's a **solved problem**: given four of
`n · i · PV · PMT · FV`, solve the fifth. A loan officer comparing three refinance scenarios, or a
student working a problem set, produces a *sequence* of these and needs to see them side by side.

Every incumbent throws that away. You get one answer, and the previous one is gone — or it lives in
opaque registers that, in the case of the app we're displacing, **silently lose their contents**:

> _"App hasn't been updated in 4+ years. **Stored registers will 0 out for no reason whatsoever.**
> Stored number in register will be exponentially higher when you recall it, again, no reason
> whatsoever."_ — Vicinno Financial Calculator, 1★, 2024-11-16

That's the gap. Not more functions — **memory of what you already did, and the ability to fix it.**

## 2. What users actually ask for

Not extrapolated from the general-calculator market — these are from **financial and professional
calculator apps**, and the tape is repeatedly the reason people *choose* one:

**They want to see the tape as they work**
> _"I love that you can easily turn sideways to quickly see the **'tape'** results of previous
> calculations."_ — Calculator HD Pro ($9.99, 11,209 r), 5★, 2025-10-23

> _"Have used daily for years. **Love seeing a tape entry as I enter**."_ — same app, 5★, 2025-04-01

> _"**I love the tape function.**"_ — same app, 5★, 2025-03-14

**They want to correct a line without redoing everything**
> _"It allows me to **go back and to fix a mistake** while I calculate — I don't have to redo the whole
> thing."_ — Calculator HD Pro Lite (51,258 r), 5★, 2025-02-13

**They want to print it** — the single most explicit unmet ask found
> _"Calculator Pro is a great app but **I would give much to have a calculator from which I could print
> the tape.**"_ — Calculator HD Pro, 5★, 2025-03-02

> _"I like **seeing and printing my transactions**."_ — Calculator HD Pro Lite, 5★, 2024-08-29

**Absence of history is a stated reason to leave**
> _"Good but **no history function**!"_ — PCalc Lite, 3★, 2022-07-15

> _"Does not support landscape mode… **There are better apps out there that show history** and support
> landscape."_ — BA Financial Calculator (PRO), 1★, 2021-01-08

**Ten of fifty** recent Calculator HD Pro reviews mention the tape, history or saving. It is not a
nice-to-have in this category; it is what the $9.99 incumbent is loved for.

## 3. What we will build

**A tape of solved problems, not of keystrokes.** Each entry records the tool, the inputs, the result,
a timestamp and an optional label:

```
▸ TVM · "123 Oak St — 30yr"      n 360 · i 6.25% · PV 420,000 · FV 0   →  PMT  −2,586.34
▸ TVM · "123 Oak St — 15yr"      n 180 · i 5.75% · PV 420,000 · FV 0   →  PMT  −3,488.85
▸ Bond · "Treasury 2031"          price 98.75 · coupon 4.25 · …        →  YTM  4.443%
```

**Required behaviour**

1. **Every solve appends a line automatically.** No "save" button — the Vicinno failure is silent loss;
   ours must be silent *retention*.
2. **Lines are correctable.** Tap a line, edit an input, the line re-solves in place. Nothing else on
   the tape changes — entries are independent solves, not a running total.
3. **A label per line**, free text, optional. This is what turns a tape into a client record.
4. **Tapes are documents.** Name one ("Refi comparison — Alvarez"), keep it, open it later. Multiple
   tapes, listed by name and date.
5. **Print and export.** System print for the tape and for a full amortization schedule or cash-flow
   list; plus plain-text and CSV share. This is the explicit unmet ask, and it's what a professional
   hands to a client.
6. **Persistence is a correctness requirement, not a convenience.** A tape must survive force-quit,
   OS update and device restart. Losing a line is the bug that killed the incumbent.

**Where it lives in the architecture** — the tape is *state*, not math. It stores the inputs and the
Kit call that produced each line; it never stores a computed number it can't re-derive. **Re-opening a
tape re-runs the Kit and must reproduce the stored result exactly**; if it can't, that's a failing test,
not a rounding excuse. Kit APIs and oracle corpora stay frozen (`PLAN.md` §5).

**Testable claims** (these belong in the app target's tests, not the Kits):
- append → close → reopen → every line's re-solve equals the stored result, bit-for-bit
- edit an input on line 2 → line 2 changes, lines 1 and 3 do not
- a tape with 1,000 entries opens and scrolls without recomputing everything
- labels, ordering and timestamps survive a round-trip through disk

## 4. What we will NOT build in v1 — and why

**iCloud sync.** It is the loudest ask in the *general* tape-calculator market (Digits: _"I wish they
had Mac support, with iCloud sync! Please add this **I would pay for it**"_) — but **zero financial
calculator reviews asked for it.** Adding CloudKit and conflict resolution on an extrapolation from a
different audience is exactly the kind of guess this project doesn't make. Build the tape as a
**document** so `DocumentGroup` + an iCloud container can be switched on later at near-zero cost, and
revisit when Par's own users ask.

**When iCloud IS added, the requirement is absolute: the same tape on every device.** A tape created on
iPhone opens, complete and current, on iPad and Mac — same labels, same ordering, same results — and an
edit on one appears on the others. Half-sync (documents that only travel one way, or a Mac app with its
own separate store) is worse than no sync, because the user stops trusting the record. That means: one
iCloud container shared by all three targets, `DocumentGroup` document storage from day one so nothing
lives in a device-local database, conflict resolution that never silently drops a line, and a visible
sync state so the user knows whether what they're looking at is current.

**Keystroke-level tape** (a running `2 + 2 =` strip). That's the general-calculator model. Par's users
work in solved problems; a keystroke strip would be noise.

**Cross-line arithmetic** (totals down the tape). Nobody asked, and it invites the "is this a
spreadsheet?" question that Numbers already answers better.

## 5. UI notes

Consistent with `PLAN.md` §6 — native components, no invented design system, no theming.

- The tape is a **list**, not a text blob: each line is a row with the label, the inputs collapsed to
  one line, and the result as the emphasised number.
- On iPhone: tape as a separate tab or a pull-up. On **iPad and Mac: tape beside the calculator**, which
  is the layout the incumbents fail at and the reason two of their fatal reviews exist.
- Dynamic Type throughout — **no pinned point sizes**, including the result column.
- `accessibilityIdentifier` on every row and on the result field.

## 6. Gate

This is **phase 5b** — after the Kits are green and the minimal UI exists, before `DESIGN_BRIEF.md`.
Do not start it while any Kit still has a `TODO(oracle):`. Report with the four testable claims in §3
demonstrated.
