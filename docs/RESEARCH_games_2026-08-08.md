# Games research — genre, puzzle gaps, and what the simulation edge is actually worth

> Four parallel research streams, 2026-08-08: genre validation, unbuilt puzzle concepts,
> underserved implemented puzzles, historical/literary sources. ToS-clean method throughout
> (Apple autocomplete with `X-Apple-Store-Front: 143441-1,29`, iTunes Search API, Customer Reviews
> RSS, Apple chart RSS). ~1,400 distinct apps sampled. Everything with a number is measured or
> sourced; speculation is marked.

---

## 1. Verdict — it turns on one question only you can answer

> **Is the constraint "$0 marketing *spend*", or "App Store *only*"?**

Measured across 992 apps and 27 genre queries: **no premium mobile game in any genre, 2024–2026,
reached traction on App Store organic search alone.** The US Top 100 Paid Games chart, parsed live,
contains **zero** new mobile-native originals discovered by App Store search — every entry is a
port, a licensed brand, a legacy hit, or a studio with a prior following.

But **Steam Next Fest and Deck Builder Fest cost nothing.** They are free, organic, zero-ad-spend
channels. If the constraint is *no spend*, they are permitted and they change the answer entirely.

| If the constraint is… | Build | Realistic ceiling |
|---|---|---|
| **No marketing spend** — Steam Next Fest allowed | **Roguelike deckbuilder with a novel mechanic**, free + **$4.99 unlock** (§3) | $100k–$1M |
| **App Store only**, immovable | **No-guess Minesweeper**, $2.99–3.99 paid (§4) | ~1k–12k ratings |

**The measured gap between the two paths is 5–7×**, quantified in §3.1.

### Three reversals from first analysis, all evidence-driven

1. **Paid-upfront is the wrong model for a game.** Apple's premium editorial surface is now
   free+unlock only (§3.4).
2. **Deckbuilder payment proof is imported, not organic** — but the *channel* that imports it is
   free (§3.1).
3. **The obscure-Nikoli generator play is already dead** — measurably, carpet-bombed in the last
   90 days (§5.1).

---

## 2. The structural finding — three streams converged independently

> **The binding constraint is impressions. A solvability oracle does not produce impressions.**

- `guaranteed solvable`, `always solvable`, `without guessing` → **zero autocomplete hits**. The
  property the engine guarantees is not something anyone types.
- The solver is a **retention and review-score asset**, not a discovery mechanism. It wins 4.8
  stars; it does not win the search result.

**This is the games-vs-utilities asymmetry, and it is the most portable finding here.** Utilities
*do* work on $0 organic search — `document scanner` returns 9 generic hits and TurboScan Pro sells
at $9.99 with 295,340 ratings. Games do not. Same store, same developer, same budget, different
discovery physics. **Do not carry utility intuitions into game decisions.**

Also measured, and it corrects a widely-quoted number: **Apple's "65% of downloads follow a search"
is the all-categories figure.** For games it was 56% (2017–18), and by 2020 **App Referrals overtook
search for games, 38% vs 35%** (Sensor Tower panel). "App Referrer" = a link tapped in
Reddit/Discord/YouTube — i.e. the imported-audience channel.

---

## 3. PATH A — Roguelike deckbuilder (if Steam Next Fest is permitted)

### 3.1 The evidence

**`roguelike` returns 10/10 purely generic autocomplete completions — the only term in a 67-term
sweep to do so.** No app titles at all:
`roguelike · roguelike games · roguelike deck builder · roguelike tower defense · roguelike shooter ·
roguelike survival · roguelike dungeon crawler · roguelike card game · roguelike rpg · roguelike td`

⚠️ **Target `roguelike deck builder`, never bare `deck builder`** — 7 of 10 completions there are TCG
*utility* intent (`mtg deck builder`, `pokemon deck builder`, `lorcana deck builder`).

**Chart occupancy:** 10 of the US Top 100 Paid Games are roguelikes/deckbuilders — the largest
independent genre cluster. **9 of the top 20 paid Card chart.**

**The entry bar is low.** Median US ratings on the Top 100 Paid Games chart is 3,890, but **17 of 99
entries have under 500** — #4 on the whole Games chart is *How Many Dudes?* at **62 ratings**. It is
a velocity chart, not a cumulative one, and the chart is itself a browse channel.

**Paid attention share** (paid apps' share of total ratings mass in each query's top 50):

| Query | total ratings | paid share | paid ≥500r |
|---|---|---|---|
| **roguelike deck builder** | 272,601 | **3.1%** | 4 |
| **deckbuilder** | 301,666 | **2.8%** | 4 |
| dungeon crawler | 410,110 | 1.5% | 2 |
| roguelike | 765,773 | 1.2% | 3 |
| escape room · visual novel · interactive fiction · nonogram · logic puzzle · sokoban · picross · minesweeper · chess puzzle | — | **0.0%** | **0** |

### The three-point calibration — this is the crux

| Game | Model | Result |
|---|---|---|
| **Dungeon Clawler** | Steam EA + iOS + Android **same day**, on Deck Builder Fest + Next Fest wishlists | **165k Steam / 45k iOS / 35k Android, ~$1M net, 2-person team** |
| **Gambonanza** | **solo dev**, same playbook, >170k Next Fest demo downloads pre-launch | **2,640 US ratings in 3 months at $5.99, #39 paid** |
| **Dungeon Within** | mobile-only, **no Steam**, dev had a prior hit | **386 US ratings in 3.5 months at $5.99** |

Gambonanza proves the playbook is **reproducible by one person**. Dungeon Within measures the
pure-mobile-organic ceiling: **5–7× lower**.

**Revenue calibration:** Balatro mobile $21.3M · Slay the Spire mobile $13.1–13.7M · Meteorfall:
Krumit's Tale $22,600 week 1 / $92,300 in ~2 months on a front-page feature · Shattered Pixel
Dungeon (solo, full-time, $4.99) 100k units late 2023 → **200k units late 2025** — ~100k units in
two years sustains one person.

### 3.2 Mass simulation is this genre's actual unmet need

908 negative reviews across 30 titles, coded. Two failure modes at 19% each, splitting cleanly by
provenance:

| | balance/RNG | mobile fit |
|---|---|---|
| **Ports** — Slay the Spire · Isaac · Nubby's · A Dark Room | 0–10% | **50–54%** |
| **Mobile-natives** — Void Tyrant · Pirates Outlaws · Gambonanza · Solitairica · Meteorfall · Dawncaster | **26–39%** | 3–13% |

Verbatim: *"NOT BALANCED AT ALL DONT BUY IT"* · *"To this day the game is still unbeatable… no
matter what you do you WILL have one of the enemies end you"* · *"There are FAR too many instances
where your run simply comes to a point where it doesn't matter what decisions you have made."*

**Every mobile-native competitor ships unproven generation.** A vectorized engine that certifies
"every seed is winnable with correct play, and the solver proves it" answers the single most-written
complaint in the genre — and the port complaints (*"touch controls are absolutely horrendous"*,
*"How does this not have portrait mode?"*, *"doesn't start up properly without an internet
connection"*) leave **mobile-native, portrait, offline, one-thumb, cloud-save** uncontested.

**Incumbent rot** (lifetime ★ → recent ★): Isaac 4.47→**3.19** · Solitairica 4.44→**3.62** · Slay the
Spire 4.25→**3.63** · Pirates Outlaws 4.47→**3.84** · Balatro 4.96→**4.11**. Only the actively
maintained solo project holds (Shattered Pixel Dungeon 4.89→4.65). **Slay the Spire, the #1 premium
deckbuilder on iOS, draws 4.6 US reviews/month.** The leaders are coasting.

### 3.3 The mechanic is the whole product

Every 2024+ winner is "deckbuilder + one unexpected system": Balatro = poker hands · Dungeon Clawler
= claw machine · CloverPit = slot machine · Peglin = pachinko · Nubby's = pinball · Gambonanza =
chess. **A pure Slay the Spire clone is dead on arrival — the store already has six at 0 ratings.**

**Pick a mechanic whose state space is simulable** — physics-lite or combinatorial, not narrative.
The solver both generates and certifies. **Ship the proof as a feature:** "every run is verified
winnable" in the subtitle, plus a per-seed post-mortem showing the line the solver found.

### 3.4 Monetization — free + $4.99 unlock, NOT paid-upfront

**Apple killed the paid-upfront editorial shelf.** A live parse of `apps.apple.com/us/games`
(2026-08-08) found **zero occurrences** of "pay once" or any no-IAP framing. The replacement is the
**"Try Before You Buy"** room — *"Games with demos you can play before you commit"* — and **all 50
apps in it are $0 download with an unlock IAP** (DREDGE $24.99, Monument Valley 3 $5.99, Slice &
Dice $8.99). There is also a "Try Before You Buy" In-App Event badge.

**A paid-upfront game is structurally excluded from the largest premium editorial surface on the
Games tab.**

**Measured revenue comparison:** Tinytouchtales converted four paid card games to free+unlock —
total revenue **+41%**, Card Crawl **+168%**. GUNCHO (free + $4.99 unlock on mobile, *identical game
sold flat $4.99 on Steam*): year 1 **Apple €78,594 vs Steam €6,407** — **12:1**.

**The cost, measured:** free+unlock buys a 1-star "bait and switch" tax. Duck Detective: 13 of 71
recent reviews are 1★ reading *"This game isn't free"* / *"SCAM."* Mitigate by **gating late**
(Wildfrost after the first boss; Peglin after a third of the game), making the unlock a **single
non-consumable with no DLC**, and stating "one payment, no subscriptions, no ads, plays offline" in
the first line of the description.

**Never add DLC.** The loudest resentment in the whole corpus is paid-then-asked-again: *"Bought
game, immediately asked to buy more"* · *"you have to buy all the extra dlc which is more than $40."*
Conversely Dungeon Clawler's top review: *"So refreshing to find a game that is designed to be
played rather than paid!"*

**Price: $4.99 unlock.** Chart median $2.99, mean $4.15; 80% of the paid chart is ≤$4.99.

### 3.5 Distribution plan — the only $0 mechanism that reliably works

Steam page up early → demo → **Deck Builder Fest** → **Steam Next Fest** → simultaneous
Steam/iOS/Android launch. Both Stray Fawn titles did exactly this. It costs nothing.

**ASO tactic worth stealing:** autocomplete for `dungeon c` returns `dungeon crawler` #1 and
`dungeon clawler` #2 — Stray Fawn's title is one letter off a high-volume generic genre term and
intercepts its typing traffic. Measurable and repeatable.

⚠️ `games like balatro`, `balatro like`, `slay the spire like` all return **zero** completions.
There is no "games like X" search behaviour on the App Store — which is *why* discovery happens on
Steam and YouTube.

**Risk:** art burden. Budget one contract pixel artist — Shattered Pixel Dungeon's 2026 blog post is
a public account of a solo dev's project stalling two years purely on artist availability.

---

## 4. PATH B — App Store only

Lower ceiling, honestly stated. But the compass fits perfectly and the engine edge is load-bearing.

### 4.1 RANK 1 — No-guess Minesweeper · the clean kill

| | |
|---|---|
| Family | **168,877 ratings** across 70 apps |
| Incumbent | **Minesweeper Puzzle Bomb** — 65,401 lifetime at 4.60, **recent 1.57**, **92% of recent reviews ≤3★** |
| The betrayal | *"I bought the pro version **when it was a one time purchase**… Now they've made it into a **yearly subscription** and decided to take my features away."* |
| Runner-up | Minesweeper Q, 18,556 ratings, **last updated 2021** |
| The paid proof | **Mineswifter, $1.99, 4.93★ — abandoned 2022 at 783 ratings** |
| Demand | `minesweeper` → **`minesweeper no ads` · `minesweeper offline` · `minesweeper classic`**, plus a title literally called *"minesweeper the clean one"* |

**The feature is requested in writing, repeatedly:**

> *"Could you update it to make the puzzles all solvable so the player is never put in a situation
> where they have to guess to win? **That would make this app the best version on the App Store!**"*

> *"After 1,731 games… an 82% incorrect to 18% correct guess rate when the final bomb has to be a
> guess."*

> *"The description is flat out lying. **This is not a guess free minesweeper game.** This is false
> advertisement."*

**And the fix demonstrably converts** — from the abandoned $1.99 app that did it:

> *"My problem with minesweeper was always that you're forced to guess… **This variation did exactly
> what I wanted.**"* · *"Being able to know the game won't end in a stupid 50/50 is so relieving."*

**Why mass simulation is the reason it can be done:** a no-guess board is not generated, it is
*searched for*. Place mines, run a constraint solver from the first click, reject if any frontier
position is ambiguous. Rejection rate at Expert density is brutal — measured elsewhere at **≈250,000
attempts per level** at density 0.41 — so you must evaluate boards in bulk to hit interactive
latency. **A scalar per-board loop is why nobody ships this.** The same solver in "count deduction
steps" mode is the difficulty grader, and difficulty becomes *which deduction pattern is required*
(1-2-1, tank-solver-only, count-parity) rather than mine density.

**Positioning:** $2.99–$3.99, one-time, no ads, no IAP, offline, iOS + macOS + Watch. Title carries
the terms autocomplete already proves: *no guessing*, *no ads*, *offline*. Ship deterministic
daily-challenge seeds — every reviewer who loves Mineswifter names the dailies.

**Risk, stated plainly:** the paid ceiling here is unproven above 783 ratings. **This is a modest
business, not a large one.**

**Precedent that matters most:** **Arcadia – Watch Games** — solo developer, **$1.99 paid-upfront,
launched Dec 2019, 12,259 ratings at 4.82, still shipping (2026-08-06)**. Its wedge was
multi-platform coverage (Watch/TV/Vision), not content depth. That is a directly transferable model.

### 4.2 RANK 2 — Logic-grid ("Einstein"/zebra) puzzles

The **only family where "levels run out" is the literal top review theme.**

Pure-play leader **Egghead's Logic Grid Puzzles: 38,775 ratings at 4.85** — the highest-rated large
app in the entire sweep — free with paid expansion packs **whose stories are recycled**:

> *"when the puzzles run out **either you pay up for more or you delete the app**"* · *"I need more
> 3x5 puzzles. **I finished them all long ago.**"* · *"I've purchased several extension packs and
> the stories are basically identical… **They don't even bother changing the names.**"*

Every rival at scale is destroyed by ad-gating: Easybrain's Clue Game (−2.71, **96% ≤3★**), Hitapps'
Cross Logic (−2.33, 84% ≤3★).

**Why simulation is the reason:** generating a good logic-grid puzzle is **clue-subset
minimisation** — enumerate candidate clue sets over a category×entity grid, confirm **uniqueness**
(exactly one satisfying assignment) *and* **minimality** (every subset ambiguous). Combinatorially
explosive; precisely bulk constraint evaluation.

⚠️ **The one place the engine does not carry the product: the puzzle is a grid but the product is
prose.** Generated stories must not read as generated.

### 4.3 RANK 3 — Nonogram / picross · largest rotting family, no paid defender

391,226 ratings, second-largest logic family. **Every large incumbent is collapsing:** Nonogram.com
193,901 → recent **2.84** (62% ≤3★, 52% ads); Picture Cross 74,319 → recent **2.51** (72% ≤3★), with
the ad-removal purchase silently converted to a monthly.

**No paid nonogram app has ever cleared 500 ratings** — the best, PathPix at 433, died in 2018.
Conceptis's Pic-a-Pix holds a 4.68 recent average (the audience is loyal) but gates content behind
**$4 packs** reviewers openly resent.

The differentiator would be puzzles generated *from* a target picture with a proof the picture is
recoverable, guaranteed **line-solvable** (never requiring look-ahead) and unique. **Ranked third
because the free-giant trap most likely applies here.**

### 4.4 Also viable — the cipher ladder

A cryptogram game where **you are not told which cipher you face**; the "aha" is identifying the
*system*, not the message.

Incumbent: **Norman Basham's *Cryptogram*, $4.99, 1,246 ratings, 4.71★ — frozen since 2021-01-13**,
a plain simple-substitution quote decoder. **Everything above simple substitution is unoccupied.**
Demand includes `cryptogram no ads`. Free giant 238,552.

**Its distinctive asset is the mystery loop** — the withheld thing is *the rule itself*, the
knowledge-gating ideal in `PRINCIPLES_game_design.md` §2. Frequency analysis on a Vigenère produces
a flat histogram, and that *failure teaches*.

Chapter content, all verified public domain: Cardan grille (Cardano, *De subtilitate*, 1550) ·
Vigenère — **actually Bellaso, 1553** · Playfair — **Wheatstone, signed 26 March 1854** ·
nomenclators (c.1400–1850) · book ciphers (**Silvestri, 1526**) · Fleissner turning grille (1880) ·
grid-poems (**Hrabanus Maurus, c.810** — a Cardan grille 700 years early) · **Sator Square** as a
layer-2 artifact.

**Layer 3:** ship one genuinely unsolved cipher of your own composition (Cicada 3301 is the
behavioural precedent). **Never claim it is historical.**

⚠️ **Negative control:** *The Guides Axiom*, the acclaimed **narrative** cipher game, is now
**free** — the premium-narrative angle did not hold a price. The **utility-plus-craft** angle did.
**Avoid "Enigma" as branding** (live marks; zero puzzle demand anyway).

### 4.5 Also viable — 3D Nonogram

Clue-minimisation **Σ₂ᵖ-complete**, counting **#P-complete**, uniqueness **NP-complete** (Kimura,
Kamehashi & Fujito, FUN 2018). **Nintendo has never shipped it on iOS.** `picross 3d` is a
recognised Apple query. Only implementation, PiKuBo, has **92 ratings**. Teachable from a screenshot.

**Name it "3D Nonogram"** — *Picross* is Nintendo's mark; "Nonogram" (Dalgety, 1990) and "Griddlers"
are the safe generics. **Catch:** no payment proof anywhere in the family.

---

## 5. Eliminations — measured

### 5.1 ⚠️ The obscure-Nikoli generator play is already dead

**Nine publishers shipped ~40 generator apps across the niche families in 2025–26. Nearly all sit at
0 ratings.**

| Publisher | apps | shipped | total ratings |
|---|---|---|---|
| hao du | 7 at $0.29 | Jun 2026 | **0** |
| Huy Huynh | 6 | 2025–26 | **0** |
| torankirite | 5 | Jul 2026 | **0** |
| Ahmet Bohur | 4 "Pro" titles | Mar–Apr 2026 | **0** |
| LUKAS NILSEN | 3 | 23 Jul 2026 | **0** |
| DAN URBANEK | 3 | Apr–May 2026 | 9 |
| chengshan zhou | 4 | 2025–26 | 65 |
| Aliaksandr Uvarau (best, 8 years in) | 6 | 2018–26 | 1,155 |

**"Queens" is the same story:** 20+ clones since Sep 2025, nearly all at 0–12 ratings; the only
winner is Kwalee's Queens Master (13,100) — a funded studio.

> **Do not enter slitherlink, masyu, nurikabe, akari, hitori, fillomino, suguru, yajilin, kakuro,
> futoshiki, hashi, or Queens.** Infinite generation is not a differentiator there — it is table
> stakes a dozen people already shipped to an audience that does not exist.

**Family totals that explain why:** slitherlink **524** · nurikabe 427 · akari 229 · hitori 208 ·
masyu 88 · fillomino **8** · yajilin **3**. And **Conceptis Ltd — the professional puzzle-content
company — has 7,617 total ratings across 9 apps after 14 years.** That is the ceiling of the entire
Nikoli space on iOS.

### 5.2 Genre eliminations

| Genre | Why |
|---|---|
| Match-3 / block / merge / word / tile | **0 paid ≥500r across 10 terms**; free giants 2.6–4M; every 2025+ winner is a funded studio doing paid UA |
| **Escape room** | highest demand purity measured (10/10 generic) and **0.0% paid share**; only 2 paid in top 50, **six ratings each** |
| Visual novel · Interactive fiction | **0.0% paid share**; zero in Top 100 Paid |
| Text adventure | 2/10 generic, and completions now dominated by LLM chatbots (`ai dungeon`, `chatventure`); one paid ≥500r, shipped 2013 |
| Metroidvania | **0 generic hits** — brand-discovered only |
| Sort puzzle | §5.3 |

**The premium-puzzle ceiling, twice measured.** Across ~120 searches only **17 paid apps** with ≥100
ratings surfaced, and only 4 are logic puzzles. Realistic solo ceiling with no imported audience:
**LYNE ($2.99, 152 ratings) to Linelight ($1.99, 997)**.

**And an imported audience does not rescue puzzle:** **Cracking the Cryptic has 688,000 YouTube
subscribers; its seven $4.99 apps hold ~911 US ratings combined.** Draknek's arc is a controlled
experiment in one studio — A Good Snowman $5.99 → 240 · Cosmic Express → 198 · A Monster's
Expedition $9.99 → **21** · Sokobond Express → **6** — then switched to free+IAP in 2025. Baba Is
You: $6.99, five years on iOS, **362 US ratings**. The Witness $9.99 → 581.

### 5.3 Why sort puzzles fail despite being perfect on paper

NP-complete and equivalent to water-sort (Ito et al., FUN 2022, arXiv:2202.09495); documented
unsolvable shipped levels; ~$280M genre. **Fails for three independent reasons:**

1. **The revenue is the wrong currency** — it is ad + IAP revenue, measuring ad inventory sold. A
   paid ad-free version does not take a slice; it exits the market.
2. **The differentiator is anti-monetisation.** The "+1 tube" that rescues an unsolvable board **is
   the rewarded-video unit**. Incumbents do not claim solvability because it is against interest —
   a 14-bottle level verifies in under a minute offline.
3. **Discovery** — head terms held by 300k-rating incumbents with UA budgets.

> **Generalise:** before treating a genre's revenue as addressable, check whether it is
> ad/IAP/subscription revenue. If so, a buy-once product does not compete for it.

---

## 6. What the simulation edge is actually worth — thesis corrected

❌ *"Some puzzles can't be generated uniquely, so nobody ships them."*
**Uniqueness is a solved engineering problem.** Simon Tatham generates **40 genres** on demand, each
with *"a unique solution that can be reached exclusively by deductive reasoning."*

✅ **The defensible thesis: generated instances have bad solve paths, and solve-path quality is
partly mechanisable.**

### Nikoli's objection splits — and the primary half is mechanisable

Source: `nikoli.co.jp/en/puzzles/sudoku/why_hand_made/`.
⚠️ *Quotes via WebFetch extraction — re-verify character-for-character before any public use.*

**Computational half — Chief Editor Kanamoto**, the *primary* stated objection: machine puzzles
often have *"no cells in which to place a number using straightforward techniques"* — no easy
break-in. **Mechanisable.**

**Aesthetic half — President Kaji**: *"good taste - an issue that computers will never comprehend"*.
**Not mechanisable.**

**Reading Nikoli's position as purely aesthetic discards their own chief editor.**

### The operationalisation already ships in code

Difficulty by **technique tier**: the generator carries a solver restricted to a named
inference-rule set per tier and rejects anything needing a rule above tier, or needing search.

| Component of solve-path quality | Mechanisable? |
|---|---|
| minimum technique tier required | **yes — already mechanised** |
| whether bifurcation is ever forced | **yes — already mechanised** |
| clue symmetry / count | cheap |
| theme / narrative | **no** |

**The edge is throughput, not capability.** Everyone can generate valid puzzles; generating at scale
and filtering for solve-path *shape* is what a vectorized engine buys.

*Verify before quoting:* Thomas Snyder — three-time World Sudoku Champion, now LinkedIn's principal
puzzlemaster — says publicly *"We have a human author for every puzzle. AI is not yet there"*, yet is
separately described as computer-generating **~1,000 variations then curating**. If accurate, the
top competitive constructor already runs generate-then-curate.

**Strongest opportunity fact:** **puzz.link's 285-genre taxonomy has zero generation infrastructure
behind it** — it is a player/editor whose database *"aggregates puzzle links from twitter and
several puzzle blogs."* But §5.1 shows almost none of those genres are searched. **Supply
opportunity, not demand.**

---

## 7. Rich and unsellable — measured zero audience

**17 terms returned literally zero autocomplete hits:** `japanese puzzle box`, `burr puzzle`,
`enigma machine`, `armchair treasure hunt`, `treasure hunt puzzle`, `weighing puzzle`, `knights and
knaves`, `martin gardner`, `lewis carroll puzzle`, `japanese geometry puzzle`, `medieval puzzle`,
`illuminated manuscript`, `hedge maze`, `secret code puzzle`, `disentanglement puzzle`, `occult
puzzle game`, `detective puzzle game`.

**5 hijacked:** `dudeney`→Disney · `sam loyd`→"sam lloyd" · `hashi`→Hashimoto's disease ·
`sangaku`→Telugu devotional apps · `senet`→Senetic (UK telecom).

Individually notable, all eliminated on demand:

- **Nine Men's Morris** — strongly solved (Gasser, ETH, 1996: the game is a draw); **no morris
  problem corpus exists anywhere**; cleanest solver-as-oracle fit in the survey; **zero US
  trademarks**. Paid leader *Advanced Mill*: **49 ratings** since 2010.
- **Mirror curves** (Chokwe *sona*, Tamil *kolam*) — best screenshot on the list; oracle is "trace
  the ray, count components". Lands inside the largest free-ad genre on the store. *Attribution to
  living cultural practice is not optional.*
- **Rithmomachia** — 11th c., only game ever in the medieval university curriculum. Fails
  30-second teachability badly; one app, 5 ratings.
- **Tafl / hnefatafl** — empty field, zero trademarks, no problem corpus. Four autocomplete hits.
  The modern hobby rests on a **mistranslation**: Linnaeus 1732 *"etiam Rex"* ("likewise the King")
  rendered in 1811 as "**except** the king."
- **Senet** — ~3100 BC, **rules are not known**. Any "solve this position" claim would be a claim
  about your own invention.
- **Royal Game of Ur** — best attestation (Finkel tablet, **3 Nov 177 BC**) but **strongly solved
  10 March 2025, open-sourced**. The solver is not a moat.

Free golden test values worth keeping: exactly **13 convex tangram configurations** (Wang & Hsiung,
1942); **119,979 solid six-piece burr assemblies** (Cutler); Chinese rings state graph ≅ path
P₍₂ⁿ₎, OEIS A000975, and **Cardano's 1550 numbers (64, 31, 95, 190) are all correct**.

---

## 8. IP landmines

- **Martin Gardner's columns are NOT public domain** — copyright transferred to Gardner (April 1975),
  now with the Martin Gardner Library Trust / MAA. **Dudeney** (1907, 1917) and **Loyd** *are* PD.
- **Nikoli owns the names, not the mechanics.** "Sudoku" is a Nikoli trademark **in Japan only**.
- **"Picross" is Nintendo's.** Use "Nonogram" or "Griddlers".
- **Multi-state logic mazes are Robert Abbott's invention** (Gardner's column, October 1962), with
  active commercial licensing history. Andrea Gilbert's tilt/plank/wriggle families © 1997–2025.
  **Highest IP risk in the survey.**
- **Shatranj** — Murray 1913 is PD, but two LIVE US registrations exist (reg 7324273, 7324274),
  class 41. Clear with counsel.
- Rules are uncopyrightable (Baker v. Selden, 101 U.S. 99; 17 U.S.C. §102(b)); **names are
  trademarks; rulebook prose and art are not free.**

---

## 9. Corrections — do not repeat these

- **"3.5 million daily LinkedIn players" is content-farm-only**, no primary source. LinkedIn has
  published only "millions" plus retention (84%/80%, later 86%/82%).
- **Cathedral labyrinths were not pilgrimage substitutes** — a modern rationalisation; earliest
  *"chemin de Jérusalem"* is late 18th century. Documented instead: an Easter ball-and-dance ritual
  (Sens 1413; Auxerre 1396–1538, outlawed 1538). The Chartres "666 feet"/272-stone/lunation claims
  are debunked (Saward).
- **Tangram is ~200 years old, not 4,000.** Loyd's *Eighth Book of Tan* (1903) invented "Professor
  Challenor" and the god Tan wholesale — OED editor **Sir James Murray**: *"the man Tan, the god
  Tan, and the Book of Tan are entirely unknown to Chinese literature, history or tradition."*
- **Chinese rings are probably not Chinese** — earliest source **Pacioli, c.1496–1509**; the name is
  an English coinage traced to 1873.
- **Nine Men's Morris is not from 1400 BC** — the Kurna dating is not defensible; some diagrams
  include Coptic crosses.
- **Unicursal/multicursal is a modern scholarly convention** (Matthews 1922, Kern 1982), not a
  medieval distinction.

---

## 10. Open questions

- [ ] **Decide the constraint: "$0 spend" or "App Store only"?** Everything follows from this.
- [ ] Re-verify the Nikoli quotes character-for-character before public use (§6)
- [ ] Verify the Snyder generate-then-curate claim — search-snippet sourcing only (§6)
- [ ] If Path B: confirm no-guess Minesweeper's ceiling — Mineswifter reached 783 and quit without
      marketing; Arcadia reached 12,259 on multi-platform coverage. Which pattern applies?
- [ ] If Path A: choose the novel mechanic, and confirm its state space is simulable before design
- [ ] Unverified, flagged by source agents: the Ninomiya himitsu-bako attribution, Fisher's 1986
      *Scientific American* citation, the Averbakh/as-Sūlī attribution, Kalah design patent D165,634
- [ ] Dungeon Clawler recent-sentiment could not be measured (`sortBy=mostRecent` returns empty)
