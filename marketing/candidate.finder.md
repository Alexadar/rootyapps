# N3 — Niche Candidate Finder (Keyword-Space Enumeration via iTunes Search API)

> **Purpose.** Find niche iOS apps worth competing with — the "big-audience, high-rating, but vulnerable" incumbents — by enumerating trade/profession keywords and profiling the ranking apps through Apple's **sanctioned iTunes Search API**. This is Net 3 of the discovery strategy. It is **100% ToS-clean**: the iTunes Search API is a public, Apple-provided web service. **No scraping. No grey-market/estimate data. No fabricated numbers.**
>
> **Reference date:** mid-2026. Re-verify the ~20 calls/min limit and field names if Apple changes them.
>
> **Goal of a run:** produce a ranked table of candidate apps matching the target profile — *large niche audience + high lifetime rating + signs of grievance (dropping current rating, subscription pricing, staleness)* — so the developer can pick which to build a buy-once competitor against.

---

## 0. Core principles (always apply)

1. **ToS-clean only.** The iTunes Search API (`itunes.apple.com/search`, `/lookup`) is sanctioned. Use it directly. Do NOT scrape App Store HTML, do NOT use Sensor Tower/data.ai/AppMagic estimate data as a source of truth, do NOT spam the endpoint.
2. **Respect the rate limit: ~20 calls/min.** Throttle (≥3s between calls) and **cache every response** (24h) keyed by the full parameter set. Exceeding the limit gets you a temporary block.
3. **Never fabricate.** Every number in the output must come from an API response field. If a field is missing, write `null` / "unknown" — never estimate. (Oracle rule.)
4. **Review count is the download proxy.** Apple never exposes download counts to anyone cleanly. `userRatingCount` is the legitimate, real, public proxy for audience size. Use it; don't pretend it's downloads, but rank by it.
5. **The target is a *shape*, not just "big."** Big-and-beloved-and-fairly-priced = bad target (can't be dislodged). The winning shape is **big audience × high lifetime rating × grievance signal**. See §4.
6. **This is discovery, not decision.** N3 surfaces candidates. Each candidate still must pass the build gates (§6) before it's a real target. Don't declare a winner from N3 alone.

---

## 1. The endpoints (verified)

### Search (find ranking apps for a keyword)
```
https://itunes.apple.com/search?term=<KEYWORD>&media=software&entity=software&country=US&limit=50
```
- `term` — URL-encoded keyword (required). Use `+` or `%20` for spaces.
- `media=software` — restrict to apps. **Required**, else you get music/movies too.
- `entity=software` (iPhone) — you may also query `entity=iPadSoftware`. Default `software`.
- `country=US` — storefront (two-letter ISO). Change to profile other markets.
- `limit` — 1–200, default 50. Use 50–100 to see the full competitive field for a term.
- Returns **JSON**. The `results` array is ordered by the store's relevance/popularity for that term (top of array ≈ top-ranking apps).

### Lookup (deep-profile one app by ID)
```
https://itunes.apple.com/lookup?id=<TRACK_ID>&country=US
```
- Faster, exact, no false positives. Use after Search to confirm/re-pull a specific candidate.
- Also supports `bundleId=<com.x.y>` instead of `id`.
- **Publisher catalog trick:** `https://itunes.apple.com/lookup?id=<ARTIST_ID>&entity=software&limit=200` returns **all apps by that developer** — use this to pull a whole specialist publisher's catalog in one call (feeds Net 2 for free).

### Customer Reviews RSS (read the wound + dates) — the grievance/liveness detector
```
https://itunes.apple.com/us/rss/customerreviews/id=<TRACK_ID>/sortBy=mostRecent/json
```
- Sanctioned, public JSON. `page=1..10` for more (recent pages only — **not** full history); `/xml` variant exists.
- Each entry returns `im:rating` (1–5), `title`, `content` (**full review text**), `updated` (**review date**), `author`. The first array entry is app metadata — skip it.
- This is what makes §4's grievance real: it returns **review text + dates programmatically**, so the agent reads the wound directly (no manual live-page read needed). See §2.9.

---

## 2. Fields to extract from each result (all real, from the JSON)

| Field | Meaning | Use |
|---|---|---|
| `trackId` | App's unique ID | Key; use for `/lookup` |
| `trackName` | App name | Display |
| `sellerName` / `artistId` | Publisher + publisher ID | Publisher-catalog pivot (§1 lookup trick) |
| `userRatingCount` | **Lifetime rating count** | **Primary size proxy — rank by this** |
| `averageUserRating` | **Lifetime avg stars** | Quality baseline |
| `userRatingCountForCurrentVersion` | Ratings on current version | Volume recency |
| `averageUserRatingForCurrentVersion` | **Current-version avg stars** | **Grievance detector** (see §4) |
| `price` / `formattedPrice` | Price (0 = free) | Monetization model |
| `currentVersionReleaseDate` | Last update date | **Staleness detector** |
| `releaseDate` | Original release | Brand age |
| `genres` | Category list | Niche confirmation |
| `description` | Full description | Read for subscription mentions, feature bloat |
| `sellerUrl` | Developer site | Manual follow-up |

> **Grievance note:** the API does NOT return whether an app is subscription-based directly. `price: 0` + `formattedPrice: "Free"` on a *utility/pro-tool* is the flag to investigate — free pro tools are almost always subscription (IAP). Confirm subscription + read the actual "buy once" backlash via the **Customer Reviews RSS feed** (§1 / §2.9) — it *does* return review text + dates programmatically, so the agent reads the wound directly (recent-only). Don't assert subscription from price alone.
>
> **Current-version ratings mirror lifetime:** Apple made ratings **cumulative**, so `userRatingCountForCurrentVersion` / `…ForCurrentVersion` avg now usually **equal** the lifetime values — the "lifetime vs current" star gap reads 0 and is **useless** for most apps. It only differs if the dev **reset** ratings on a version bump. Don't rely on it; use §2.9 review-reading instead.

---

## 2.9 [AUTO] Review-signal reading — the real liveness & grievance detector

The single most useful ToS-clean signal for **"is this app dead, and *why*"** is the Customer Reviews RSS feed (§1). Star averages hide the truth; the **recent review text + its date** reveal it. This supersedes the old assumption that review text needs a manual live-page read — the agent reads the wound directly.

**Two things it exposes that the numbers can't:**
1. **Liveness / velocity — from the review *dates*.** New reviews arriving weekly = alive; newest is months old = dying; none = dead / no real audience. Reviews-per-month (computed from the dates) is the real usage-momentum proxy.
2. **The wound (grievance), verbatim — from the recent 1–3★ *text*.** Grep the high-value patterns:
   - **"paid again" / "already purchased" / "now wants money" / "subscription"** → buy-once backlash *(the thesis wound)*
   - **"no support" / "no response" / "emailed, nothing"** → abandonment
   - **"not updated" / "crashes" / "broken on iOS <x>" / "please update"** → dev-abandoned / breaking
   - **nag-prompt spam ("asks me to review")**, **"$X a week"** → dark-pattern / predatory-pricing rage

**The liveness × sentiment matrix — LABEL each candidate with one of these:**
| Recent reviews | Update age | **Label** |
|---|---|---|
| arriving + recent **1–3★ grievances** (pay-again / no-support / crash) | stale or milking | **STRONG TARGET** — real wound, take the angry users |
| arriving + recent **5★ praise** | stale | **BELOVED** — alive but loved → weak grievance, hard to dislodge |
| beloved **paid** app + recent *"please update / breaks on new iOS"* | abandoned | **ADOPT-THE-ORPHAN** — proven payers begging for a maintained successor |
| newest review very old / none | any | **DEAD / NO AUDIENCE** — skip (empty ≠ opportunity) |

**Worked example (2026-07) — the feet-&-inches calculator niche (a STRONG TARGET found only by reading dated review text):**
- `Feet & Inches Tape Calculator` — 9,260 ratings, **4.4★**, free — recent dated 1★: *"already purchased this years ago, all of a sudden they're making me pay again"*, *"No support — emailed 5 days ago, no response"*, *"not updated, crashes"* + nag spam → **STRONG TARGET**.
- `Digits Tape Calculator` — $1.99, 4.8★, last updated **2019** — recent *"sad it's not updated anymore"*, *"truncates entries on iOS 15.7, please update"* → **ADOPT-THE-ORPHAN**.
- `Tape Measure™` — 87k, 4.4★ — *"$9.99 a week for a ruler?!"* → predatory-subscription rage (note: AR product, different niche).
- Verdict: real audience × documented pay-again/abandonment/no-support wounds × pure public math (feet-inch fractions) × no copyright/data/liability = the cleanest **big × grievance × buy-once** target in the scan — invisible in the star average, obvious in the dated text.

**Honesty caveats:** recent-only (current mood, not a trend line — **forward-poll** weekly for real velocity); still no sales/downloads (reviews are the proxy, never the number); read enough recent reviews to judge the *dominant* sentiment, never one outlier.

## 2.10 [AUTO] Apple autocomplete — the demand detector (and its trap)

The single cheapest demand test available. **Empty autocomplete on the core term is close to fatal.**

```
https://search.itunes.apple.com/WebObjects/MZSearchHints.woa/wa/hints?clientApplication=Software&term=X
```

**Two operational facts that cost a day to learn:**

1. **It REQUIRES the header `X-Apple-Store-Front: 143441-1,29`** (US). Without it the endpoint returns an
   **empty array** and looks like "no demand" for everything you test.
2. **The response is an XML plist, not JSON.** Parse `<string>` elements; filter out anything starting
   with `http` and the literal `Suggestions`.

### ⚠ THE TRAP: autocomplete can measure SUPPLY, not demand

If every hint returned is an existing **app title**, the term is crowded with shovelware — it does not
prove query volume. **Check each hint against the actual catalogue before calling it demand.**

Worked failure: `gear ratio` returned six rich hints — `bicycle gear ratio app`, `gear ratio calculator
lite`, `gear ratio calculator 2`, `gear ratio speed calc`, `cog: gear ratio calculator`,
`moto gear ratio calculator rpm`. Read as demand, it looked excellent. Every one was the **name of an
app**, and nine of those apps had shipped in seven months, all at **0–1 ratings**. Rich autocomplete
meant the term was saturated, not wanted.

A *generic* completion (the bare term, or term + free/games/no ads/offline/for adults) is demand.
A completion that is somebody's product name is supply.

### WEB DEMAND IS NOT APP STORE DEMAND

**25 of 30 exotic calculator domains returned completely empty autocomplete** — VPD, saponification,
K-factor, rolling offset, birdsmouth, compression ratio, turbo sizing, mesh-to-micron, PCR annealing,
Shannon index, Altman Z-score, hydroponics, beekeeping, cheese making, pottery glaze, sourdough
hydration. Omni Calculator hosts ~3,900 calculators because that demand lives on the **web**: someone
needs it once, Googles it, uses a page, leaves. **That is SEO, not ASO** — a different channel a paid
offline app cannot enter. Never infer App Store demand from web popularity.

---

## 3. The keyword seed list (enumerate the demand side)

Run Search for each. These are **trades/professions with public, testable math** (the buildable universe). Expand as needed.

**Construction core (KerfCalc-adjacent):**
`framing calculator`, `construction calculator`, `rafter calculator`, `stair calculator`, `roof pitch calculator`, `concrete calculator`, `masonry calculator`, `rebar calculator`, `feet inches calculator`, `board foot calculator`, `tile calculator`, `drywall calculator`, `grading excavation calculator`

**Mechanical / metal trades:**
`pipe trades calculator`, `welding calculator`, `machinist calculator`, `speeds feeds calculator`, `sheet metal calculator`, `hvac calculator`, `duct calculator`, `refrigeration calculator`

**Electrical / plumbing (⚠️ copyright-gate risk — see §6):**
`electrical calculator`, `conduit fill calculator`, `voltage drop calculator`, `plumbing calculator`, `pipe sizing calculator`

**Surveying / land:**
`cogo calculator`, `land survey calculator`, `traverse calculator`, `acreage calculator`

**Other public-math pro niches:**
`towing weight calculator`, `trailer weight calculator`, `marine navigation calculator`, `tide calculator`, `ham radio calculator`, `antenna calculator`, `photography calculator` *(likely served-free — verify)*, `ballistics calculator`, `woodworking calculator`, `cabinet calculator`, `paint calculator`, `fence calculator`

> For each keyword, also record which **publishers** recur (e.g. Calculated Industries). A publisher that appears across many keywords is a Net-2 goldmine — pull their full catalog via the artist-ID lookup trick.

---

## 4. Scoring — the grievance-shaped filter

For each app, compute a candidate score. The magic quadrant is **big × good-lifetime × grievance**.

**Size (audience real?):**
- `userRatingCount` ≥ 20,000 → strong (proven large niche)
- 5,000–20,000 → good (lucrative, too small for big studios to defend)
- 2,000–5,000 → marginal (real but thin)
- < 2,000 → skip unless the niche is tiny by nature
- Sweet spot: **5K–50K** — big enough to matter, small enough to be underdefended.

**Grievance signals (any one = investigate; two+ = strong target):**
1. **Rating gap (⚠️ usually unavailable):** `averageUserRating` (lifetime) − `averageUserRatingForCurrentVersion` (current) ≥ **0.4 stars**. In theory a high lifetime with a sagging current rating = users turning on it. **But** Apple's cumulative ratings mean current ≈ lifetime for most apps (gap = 0, useless); it only differs if the dev reset on a version bump. **The reliable grievance signal is the dated review text — §2.9, not this gap.**
2. **Subscription flag:** `price: 0` on a professional/utility tool → investigate for subscription + "buy once" reviews (manual review-read).
3. **Staleness:** `currentVersionReleaseDate` > **12 months** ago on an app with real audience = poorly defended niche.
4. **Brand age × model shift:** old `releaseDate` (established brand) + now free/subscription = the Construction Master pattern.

**Score = size tier + number of grievance signals.** Rank descending. Flag the top candidates for the build-gate check (§6).

**Anti-target (down-rank):** big audience + high current rating + reasonable one-time price + recently updated = beloved and defended. Don't pick fights with these; that's the "good and free" wall.

---

## 5. Run procedure

1. **Confirm scope.** US storefront unless told otherwise. Confirm the seed keyword list (add/remove per the developer's interest).
2. **Search each keyword** (`media=software&entity=software&limit=50`), throttled ≥3s, cached. Collect the top ~15–20 results per term.
3. **Deduplicate** apps across keywords (same `trackId`). Note how many keywords each app ranks for (breadth = strength).
4. **Extract fields** (§2) for each unique app.
5. **Score** each (§4).
6. **Publisher pivot:** for any publisher recurring across ≥3 keywords, pull their full catalog via the artist-ID lookup and score those too.
7. **Flag manual-review items:** any `price:0` pro tool (confirm subscription + read live reviews for grievance — API can't return review text or subscription status).
8. **Apply build gates** (§6) to the top ~15 candidates.
9. **Output** the ranked table (§7).

### 5.1 THE INVERTED CENSUS — prefer this to keyword sweeping

Keyword-first sweeping costs days and, per §2.10, mostly measures supply. **Invert it:**

> Census the catalogue directly for **paid apps above ~200 ratings** in the target space, then work
> backwards to the job.

**Payable niches cannot hide — they show up as paid rating mass.** This is cheap (hours, not days) and
**terminal**: when it returns the same names it returned last time, the space is exhausted and further
sweeping is waste.

Run against the whole trade-calculator space it surfaced exactly two payable niches — conduit bending
(~5,552 combined paid ratings) and duct sizing (~731) — both held by healthy, actively-maintained
4.5★+ incumbents. That is close to a terminal finding for the paid-trade-calculator thesis, reached in
hours after weeks of keyword work had not reached it.

**Use paid rating mass as the single discriminator.** It separates real from imaginary cleanly:

| Field | Combined **paid** ratings | Verdict |
|---|---|---|
| conduit bending | ~5,552 | payable, defended |
| duct sizing | ~731 | payable, defended |
| crown molding | 115 | marginal |
| locksmith SFIC | 9 | not payable |
| sheet metal layout | 6 | not payable |
| ag/horticulture, all paid calcs 2020–2026 | **0** | not payable |

---

## 6. Build gates (a candidate must survive these to be a real target)

These are the *strategy* gates (not Apple rules). N3 finds candidates; these decide if a candidate is buildable/winnable.

1. **Public-math oracle:** is the app's core math public and externally testable against a cited source (textbook, standard, open-source tool)? If the value is a proprietary dataset (parcel data, navdata) not public math → **data-dependency dealbreaker**, skip (this is the LandGlide/ForeFlight trap).
2. **No copyright wall:** does the app depend on a copyrighted standard's *tables* (NEC/NFPA for electrical, ACCA Manual J for HVAC, NFPA generally)? Encoding a public *procedure* is fine; reproducing copyrighted *tables* is not. If the value is the copyrighted table → **skip or redesign** (user inputs their own spec values instead of you shipping the table).
3. **No free manufacturer/retailer tool dominance:** does a hardware vendor give away this calculator as lead-gen (solar sizing, Sandvik speeds/feeds)? If the math is someone's marketing budget → **not monetizable as buy-once**, skip.
4. **Liability class:** is a wrong answer self-revealing and harmless (framing: board doesn't fit) or silent and catastrophic (electrical wiring: fire; medical dosage: death)? Low/self-revealing = fine. Fire/death class = heavy liability, flag or avoid.
5. **Grievance is real:** confirm (via live reviews, manual) that there's actual "buy once" / "used to own it" backlash or a genuine quality gap — not just a price you personally dislike.

### Gates 6–10 — added 2026-08-02, each one learned by getting it wrong first

6. **FREQUENCY BEATS AUDIENCE SIZE.** Is the job done **daily or weekly by the same person**, or once a
   year? Apps that own a *trade* succeed; apps that do a *calculation* fail.
   Measured: conduit bending = 3 paid apps, **~5,552 combined paid ratings**, because an electrician
   bends conduit all day. Gear ratio = **15 apps, ~15 combined ratings**, because you compute it once
   when you lift the truck. Same math quality, same licensing, opposite outcomes.
   **A once-a-year job cannot sustain an app no matter how well built.**

7. **OUTPUT TYPE PREDICTS CAPTURE.** *A manufacturer gives the calculation away when the output is a
   **purchase quantity**. Nobody captures a calculation whose output is a **machine setting**.*
   Quantity-output → captured, every time: paint gallons (Sherwin-Williams 13,625 r), fabric yards
   (Robert Kaufman), fertiliser/tank mix (Bayer, Corteva), irrigation runtime (Orbit 317,643 r,
   Rachio 154,085 r, Hunter 58,778 r), steel weight, tile/drywall takeoff. **The calculation is the
   order form** — the vendor outspends you and prices at zero, permanently.
   Setting-output → uncaptured: conduit bend marks, crown miter angle, press-brake deduction, SFIC
   pinning. Nobody sells anything by the degree.
   **Use as a pre-filter: any calculation whose answer is "how much to buy" is dead before you measure it.**

8. **POINT OF WORK.** Does the tradesperson compute this **standing up holding the workpiece**, or
   **sitting at a desk inside vendor software**? Desk-bound is invisible on the App Store even at daily
   frequency — stone fabricators nest in Slabsmith, opticians transpose in VisionWeb, dental labs in CAD,
   locksmiths in InstaCode. All pass gate 6 and all return **empty autocomplete**.
   **Empty autocomplete on a high-frequency trade usually means "they already do it on a bigger screen,"
   not "they don't need it"** — and that is unrecoverable by building a better phone app.

9. **SURFACE AREA DEFENDS PRICE.** One formula = a shovelware farm. Sheet-metal flat pattern is
   essentially one equation: result is a seven-seller farm, nine new entrants in a month, and **the
   best-selling paid app in the field has 6 ratings**. Conduit bending has offsets, saddles, three- and
   four-point, segmented, rolling, shrink, gain, multi-shot — result: $6.99 × 3,852 r and $7.99 × 1,700 r.

10. **PAYMENT PROOF — THE CORRECTED RULE.** A hard "no payment proof → skip" gate is **wrong**: it
    excludes every unexploited market by definition and steers you only into contested ones. What payment
    proof actually tests is *does this audience buy at all*, and that is only decisive when they've
    demonstrably refused.

    | Situation | Read |
    |---|---|
    | No payment proof **+ thriving free incumbent** | Audience was offered paid and chose free. **Dead.** |
    | No payment proof **+ nobody tried properly** | Open market. **This is the opportunity.** |
    | Payment proof exists | De-risked, but you're entering a fight |

    The decisive column is **"is there a free giant?"**, not "is anyone making money."
    Unit converters are row one: free app **190,098 r** vs its own paid twin **8,408 r** — 22:1.

**A candidate must clear all ten.** Gates 6–8 kill most things before you spend a day measuring.

### The free-giant roster (verified 2026-07-29, US)

A free incumbent funded by an equipment maker, retailer or industry platform **cannot be beaten by a
paid app**. Recognise the pattern on sight:

irrigation = **Hunter Industries 58,778 r** · HVAC = **Copeland 17,072 r** + Bluon 4,451 · pool =
**Clorox 29,019 r** + Pentair 22,993 · plumbing = **Calculated Industries "Pipe Trades Pro" 4,202 r** ·
welding = Miller / Hobart / Lincoln Electric / Fronius · paving = Caterpillar · ag spray = Bayer ·
trucking = **Trucker Path 147,201 r** · landscaping/asphalt/concrete = Calc Hub LLC ·
window coverings = Hunter Douglas 2,379 r.

⚠ **Check the price is real.** Calculated Industries' *Construction Master Pro Calc* lists as "Free" but
its description says *"FREE Try Before You Buy 14 Day Trial."* That is a **paid product with a trial** —
39,096 r at 4.84★ and 1.12M downloads — which makes it *payment proof*, not a giveaway. Read the
description before classifying anything as a manufacturer freebie.

---

## 7. Required output

```
## N3 CANDIDATE RUN — <date> — <storefront>

### Ranked candidates
| Rank | App | Publisher | RatingCount (size) | ★ | Price/Model | Last update | Newest review (recency) | Recent wound (dated 1–3★ theme) | Build gates | **Label** |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | ... | ... | 9,260 | 4.4 | Free/sub* | 2025-11 | 2026-07 (alive) | "paid again" + "no support" + crashes | oracle✓ copyright✓ mfr✓ liability:low | **STRONG TARGET** |

*= subscription unconfirmed via API; confirmed via reviews-RSS read (§2.9).
Label ∈ {STRONG TARGET · BELOVED · ADOPT-THE-ORPHAN · DEAD/NO-AUDIENCE} — per the §2.9 matrix. Star average alone is not the signal; the **dated review text** is.

### Publisher goldmines (recurring across niches)
| Publisher | # niches | Catalog size | Notes |

### Flagged for manual review (price:0 pro tools — confirm subscription + read reviews)
- <app> — <why>

### Build-gate casualties (found but disqualified)
| App | Killed by | Note |

### ⭐ Top 3 build targets (cleared all gates + high score)
1. ...
2. ...
3. ...

### 🙋 Human must do next: <read live reviews on flagged apps; confirm subscription; validate grievance>
### ⚠️ Data caveats: review count = size proxy not downloads; subscription status not in API; review text not in API (manual read required).
```

---

## 8. Hard limits & honesty (state these when relevant)

- **The API does NOT return:** download counts (use `userRatingCount` as proxy), subscription status explicitly (infer from `price:0` on pro tools, confirm via reviews), keyword-search *volume* (Apple publishes to no one cleanly), or a **historical** review/rating time-series (snapshot only — forward-poll for velocity). **Correction:** review *text + dates* ARE available via the sanctioned **Customer Reviews RSS feed** (§1 / §2.9), recent-only — so the agent reads the grievance directly, no manual live-page read required. And `userRatingCountForCurrentVersion` now usually **mirrors** lifetime (cumulative ratings), so the lifetime-vs-current star gap is unavailable unless the dev reset.
- **N3 is niche-scoped by design.** It profiles the leaders *within* keywords you already chose. It does NOT and CANNOT scan the whole store or rank all apps by size — no clean feed exists for that, and that's fine: you never wanted the whole store, you wanted the leaders inside buildable niches.
- **Estimate leaderboards (Sensor Tower et al.) are scraping-based** and niche-inaccurate. You may *read their published articles* for candidate *names*, but verify every name and all numbers through this API. Never treat their estimates as truth or wire them into a pipeline.
- **Grievance is not in the numbers alone.** The rating gap flags it; a human confirms it by reading the actual "let me buy it once" reviews. Numbers find the candidate; reviews confirm the wound.

---

## 9. One-paragraph summary for the agent

Enumerate trade/profession keywords with public math; for each, query the sanctioned iTunes Search API (`media=software&entity=software`, ≤20 calls/min, cached); extract real fields — `userRatingCount` (size proxy), lifetime vs current `averageUserRating` (grievance detector), `price` (subscription flag), `currentVersionReleaseDate` (staleness); score by the magic quadrant *big audience × high lifetime rating × grievance signal*; pull recurring publishers' full catalogs via the artist-ID lookup; flag `price:0` pro tools for manual review-reading (API returns neither review text nor subscription status); run survivors through the five build gates (public-math oracle, no copyright-table wall, no free-manufacturer-tool dominance, acceptable liability class, real confirmed grievance); output a ranked candidate table with top-3 build targets. Never scrape, never use estimate data as truth, never fabricate a number, and never claim grievance from price alone — a human reads the reviews to confirm the wound.
