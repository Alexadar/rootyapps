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

> **Grievance note:** the API does NOT return whether an app is subscription-based directly. `price: 0` + `formattedPrice: "Free"` on a *utility/pro-tool* is the flag to investigate — free pro tools are almost always subscription (IAP). Confirm subscription + read the actual "buy once" backlash by having a human open the live App Store reviews page (API doesn't return review text). Flag these for manual review; don't assert subscription from price alone.

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
1. **Rating gap:** `averageUserRating` (lifetime) − `averageUserRatingForCurrentVersion` (current) ≥ **0.4 stars**. A high lifetime rating with a sagging current rating = users turning on it (classic post-subscription backlash).
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

---

## 6. Build gates (a candidate must survive these to be a real target)

These are the *strategy* gates (not Apple rules). N3 finds candidates; these decide if a candidate is buildable/winnable.

1. **Public-math oracle:** is the app's core math public and externally testable against a cited source (textbook, standard, open-source tool)? If the value is a proprietary dataset (parcel data, navdata) not public math → **data-dependency dealbreaker**, skip (this is the LandGlide/ForeFlight trap).
2. **No copyright wall:** does the app depend on a copyrighted standard's *tables* (NEC/NFPA for electrical, ACCA Manual J for HVAC, NFPA generally)? Encoding a public *procedure* is fine; reproducing copyrighted *tables* is not. If the value is the copyrighted table → **skip or redesign** (user inputs their own spec values instead of you shipping the table).
3. **No free manufacturer/retailer tool dominance:** does a hardware vendor give away this calculator as lead-gen (solar sizing, Sandvik speeds/feeds)? If the math is someone's marketing budget → **not monetizable as buy-once**, skip.
4. **Liability class:** is a wrong answer self-revealing and harmless (framing: board doesn't fit) or silent and catastrophic (electrical wiring: fire; medical dosage: death)? Low/self-revealing = fine. Fire/death class = heavy liability, flag or avoid.
5. **Grievance is real:** confirm (via live reviews, manual) that there's actual "buy once" / "used to own it" backlash or a genuine quality gap — not just a price you personally dislike.

A candidate that clears all five **and** scores high on §4 is a genuine build target.

---

## 7. Required output

```
## N3 CANDIDATE RUN — <date> — <storefront>

### Ranked candidates
| Rank | App | Publisher | RatingCount (size) | Lifetime★ | Current★ | Gap | Price/Model | Last update | Grievance signals | Build gates | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | ... | ... | 38,000 | 4.8 | 4.1 | 0.7 | Free/subscription* | 2026-05 | sub + gap | oracle✓ copyright✓ mfr✓ liability:low | STRONG TARGET |

*= subscription unconfirmed via API; flagged for manual review-read.

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

- **The API does NOT return:** download counts (use `userRatingCount` as proxy), review *text* (human must open live page), subscription status explicitly (infer from `price:0` on pro tools, confirm manually), keyword-search *volume* (Apple publishes to no one cleanly).
- **N3 is niche-scoped by design.** It profiles the leaders *within* keywords you already chose. It does NOT and CANNOT scan the whole store or rank all apps by size — no clean feed exists for that, and that's fine: you never wanted the whole store, you wanted the leaders inside buildable niches.
- **Estimate leaderboards (Sensor Tower et al.) are scraping-based** and niche-inaccurate. You may *read their published articles* for candidate *names*, but verify every name and all numbers through this API. Never treat their estimates as truth or wire them into a pipeline.
- **Grievance is not in the numbers alone.** The rating gap flags it; a human confirms it by reading the actual "let me buy it once" reviews. Numbers find the candidate; reviews confirm the wound.

---

## 9. One-paragraph summary for the agent

Enumerate trade/profession keywords with public math; for each, query the sanctioned iTunes Search API (`media=software&entity=software`, ≤20 calls/min, cached); extract real fields — `userRatingCount` (size proxy), lifetime vs current `averageUserRating` (grievance detector), `price` (subscription flag), `currentVersionReleaseDate` (staleness); score by the magic quadrant *big audience × high lifetime rating × grievance signal*; pull recurring publishers' full catalogs via the artist-ID lookup; flag `price:0` pro tools for manual review-reading (API returns neither review text nor subscription status); run survivors through the five build gates (public-math oracle, no copyright-table wall, no free-manufacturer-tool dominance, acceptable liability class, real confirmed grievance); output a ranked candidate table with top-3 build targets. Never scrape, never use estimate data as truth, never fabricate a number, and never claim grievance from price alone — a human reads the reviews to confirm the wound.
