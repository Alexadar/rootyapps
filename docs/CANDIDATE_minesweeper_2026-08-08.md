# Candidate — no-guess Minesweeper

> Parked for later decision. Measured 2026-08-08 (Apple autocomplete with
> `X-Apple-Store-Front: 143441-1,29`, iTunes Search API, Customer Reviews RSS).
> Extracted from `RESEARCH_games_2026-08-08.md` §4.1 plus a live field check.

---

## 1. One-line thesis

Every Minesweeper board is **generated and proved solvable by pure deduction from the opening
click** — no 50/50, no coin flip, ever, including at Expert and on custom sizes. Sold once, no ads,
no IAP, offline, across iPhone/iPad/Mac/Watch.

---

## 2. Why it's a candidate

| | Measured |
|---|---|
| Family size | **168,877 ratings** across ~70 apps |
| Free incumbent | **Minesweeper Puzzle Bomb** — 65,401 lifetime ratings at 4.60 |
| **Its recent sentiment** | **1.57★ average, 92% of recent reviews ≤3★** |
| The betrayal | converted a one-time ad-removal purchase into a **yearly subscription** |
| Runner-up | Minesweeper Q — 18,556 ratings, **last updated 2021** |
| Prior paid proof | **Mineswifter, $1.99, 4.93★ — abandoned 2022 at 783 ratings** |
| Demand | `minesweeper` completes to **`minesweeper no ads` · `minesweeper offline` · `minesweeper classic`** — plus a rival literally titled *"minesweeper the clean one"* |

### The feature is requested in writing, repeatedly

> *"Could you update it to make the puzzles all solvable so the player is never put in a situation
> where they have to guess to win? **That would make this app the best version on the App Store!**"*
> — 4★, Minesweeper Q

> *"After 1,731 games, I currently sit at a 38.68% win rate (advanced) and an **82% incorrect to 18%
> correct guess rate** when the final bomb has to be a guess."* — 1★, Minesweeper Q

> *"The description is flat out lying. **This is not a guess free minesweeper game.** This is false
> advertisement."* — 1★, Minesweeper Classic: Retro

> *"if you do anything harder than medium theres almost a 100% there will be a 50/50 somewhere."*
> — 2★, Minesweeper Classic: Retro

### And the fix demonstrably converts

From the abandoned $1.99 app that shipped it:

> *"My problem with minesweeper was always that you're forced to guess. Imo, that should never be
> the case in a puzzle game. **This variation did exactly what I wanted.**"* — 4★, Mineswifter

> *"Being able to know the game won't end in a stupid 50/50 is so relieving."* — 5★, Mineswifter

### The subscription betrayal, verbatim

> *"I bought the pro version **when it was a one time purchase** so i could avoid adds. Now, they've
> made it into a **yearly subscription** and decided to take my features away."*
> — 3★, Minesweeper Puzzle Bomb (65k ratings)

This is the `PRINCIPLES_monetization` condition exactly: buy-once is a weapon **where rivals took
money and then moved to subscription**.

---

## 3. Live field check — 2026-08-08

**54 Minesweeper-titled apps: 52 free, 2 paid.**

| Top free | Ratings | Released | Updated |
|---|---|---|---|
| Minesweeper Puzzle Bomb | 65,401 | 2009-03 | 2026-05 |
| Minesweeper Classic: Retro | 21,290 | 2017-09 | 2026-05 |
| Minesweeper Q | 18,556 | 2011-03 | **2021-05** |
| Minesweeper Classic Bomb Games | 11,185 | 2019-04 | 2026-08 |
| Infinite Minesweeper GRYKUBY | 3,416 | 2024-04 | 2026-07 |
| **Minesweeper NETFLIX** | 2,398 | 2024-07 | 2025-10 |

**Every paid app on the store:**

| | Price | Ratings | Released |
|---|---|---|---|
| Minesweeper – Mine Finder Pro | $0.99 | **34** | 2012-09 |
| **Minesweeper – No ads, No Guess** | **$0.49** | **5** | **2026-06** |

⚠️ **Someone shipped this exact concept two months ago.** Priced at **$0.49**, five ratings after
two months. Two readings, both true:

- the paid slot is genuinely empty and nobody has taken it
- **the concept alone does not sell.** A race-to-the-bottom price signals disposable and gets
  treated that way

Note: Mineswifter no longer appears in search results — likely delisted since its 2022 abandonment.

---

## 4. Why mass simulation is the reason it can be done

**A no-guess board is not generated — it is searched for.** Place mines, run a constraint solver
from the first click, reject if any frontier position is ambiguous.

The rejection rate is the whole problem. Measured elsewhere: **≈250,000 attempts per level** at
density 0.41 on a shipped game; at density 0.25 on 16×30 *"almost no game is solvable."* Kunz
(TU Berlin, 2024) measured attempts-per-accepted-board at **1.21 / 1.61 / 9.75** for
Beginner/Intermediate/Expert, with ~97–98% of solver work being trivial single-point deduction.

**A scalar per-board loop is why nobody ships this at Expert on custom sizes.** A vectorized engine
solving millions of candidate boards is exactly the tool.

**Better architecture than generate-and-reject:** Simon Tatham's **perturb-and-repair** — move the
offending mine rather than resampling the board — degrades linearly rather than exponentially with
density. Worth adopting rather than rediscovering.

**The same solver is the difficulty grader.** Run it in "count the deduction steps" mode and
difficulty becomes *which deduction pattern is required* — 1-2-1, tank-solver-only, count-parity —
rather than mine density. No competitor grades this way.

**Complexity note (for accuracy, not marketing):** Kaye's *Minesweeper is NP-complete* covers
**consistency**. The problem players actually face — **inference** — is **coNP-complete**
(Scott/Stege/van Rooij). Maximising win probability is PP-hard.

---

## 5. Business case

**Rating-rate anchor:** Shattered Pixel Dungeon has 4,061 US ratings against 200,000+ units →
roughly a **5–7% rating rate**. Used for everything below; it is an order-of-magnitude estimate,
not a forecast.

| Scenario | Ratings | Implied US units | Lifetime net @ $2.99, 85% SBP | Per year |
|---|---|---|---|---|
| Mineswifter path (no marketing, quit) | 783 | ~13,000 | ~$33k | **~$14k/yr** |
| **Arcadia path** (craft + multi-platform) | 12,259 | ~200,000 | **~$500k** | **~$50k/yr** |

**The precedent that matters:** **Arcadia – Watch Games** — solo developer, **$1.99 paid-upfront,
launched Dec 2019, 12,259 ratings at 4.82, still shipping as of 2026-08-06.** Its wedge was
**multi-platform coverage (Watch/TV/Vision), not content depth.** Directly transferable.

**Price: $2.99–$3.99.** Not $0.49 — see §3.

---

## 6. The honest case against

1. **No-guess is already solved and free elsewhere.** minesweeper.online ships it with leaderboards
   (10M players), Tatham's Mines is free, Antimine is open source and already uses "no guess
   minesweeper" as a store keyword. **The buyer wants a clean native iOS app, not the algorithm.**
2. **The algorithm is not the differentiator; craft and platform reach are.** Arcadia proves the
   winning wedge, and the $0.49 June 2026 entrant proves the losing one.
3. **Ceiling is modest.** The optimistic case is ~$50k/yr. This is a real small business, not a
   company.
4. **52 free competitors**, several actively maintained, one of them Netflix.
5. Two research agents disagreed: one called this the clean kill, the other called the space
   **saturated**. Both were right about different surfaces — web/open-source is saturated, the
   paid native iOS slot is empty.

---

## 7. If built — the shape

- **$2.99–$3.99, one-time. No ads, no IAP, no subscription. Offline.**
- **iPhone + iPad + Mac + Watch** — this is the Arcadia wedge and the actual differentiator
- **Title carries the terms autocomplete already proves**: *no guessing*, *no ads*, *offline*.
  Head noun stays `Minesweeper`
- **Deterministic daily-challenge seeds** — every reviewer who loved Mineswifter names the dailies
- **Difficulty by deduction pattern**, not mine density — and say so, it is legible and unique
- **Structural bonus:** the "wrong number on the tile" bugs plaguing the incumbent become impossible
  by construction
- Adopt **perturb-and-repair** (§4) rather than naive generate-and-reject

**Oracle for the Kit:** a board is accepted only if the constraint solver closes it from the opening
click with no ambiguous frontier position. That is a genuine, provable test oracle — the house
pattern, applied to a game.

---

## 8. Open questions

- [ ] Which precedent applies — Mineswifter (783, quit) or Arcadia (12,259, thriving)? The
      difference is craft and platform reach, both of which are choices rather than luck
- [ ] Does the Watch version work? Minesweeper on a small screen is a real design question, and it
      is the Arcadia wedge
- [ ] Watch the $0.49 June entrant — if it starts moving, the window narrows
- [ ] Verify the rating-rate assumption against your own Apple Ads conversion data once the
      Storypole/Marine Nav campaigns produce numbers
- [ ] Decide against the alternative first: this is the **App-Store-only** answer. If Steam Next
      Fest is permitted, `RESEARCH_games_2026-08-08.md` §3 is the higher-ceiling path
