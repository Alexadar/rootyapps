# ASO AUDIT — Marine Nav — 2026-07-26

Run per `marketing/ASO_APP_PROMPT.md`, governed by `marketing/autoaso.md` (§6, §6.5 binding).
**Draft only. Nothing submitted, no version created, no listing touched.**

## Scope note — this is a PRE-LAUNCH draft, not an audit

`marinenav` is **not in App Store Connect** (verified via the ASC API: 13 apps in the account,
none with a `marinenav` bundle id or "Marine" name). So:

- **§1 "pull the LIVE metadata"** — N/A. There is no listing to read.
- **§2 "positional diagnostic"** — N/A **for our app**. An unpublished app cannot be found in
  any search result, so "NOT FOUND" would carry no information. Re-run it 2–3 weeks after the
  first release; that is when it becomes the useful instrument.

What *was* run: §4 incumbent research, §3 audit applied to the drafted fields, §5 field set.

## ⚠️ The niche premise does not survive contact with the data

`docs/n3_revalidation_2026-07-26.md` framed this app around **Tide Charts — 111k ratings, 4.8★,
49.6 months stale**. That single fact is still true (measured today: 111,007 ratings, 50 months
stale). **The conclusion drawn from it is not.** Profiling the actual ranking field:

| Query | #1 | #1 ratings | #1 price | #1 stale | Free apps in top 10 | Freshly updated (≤3 mo) |
|---|---|---|---|---|---|---|
| tide chart | Tide Charts | 111,007 | Free | 50 mo | 10/10 | 8/10 |
| tide times | My Tide Times | 16,969 | Free | 0 mo | 9/10 | 7/10 |
| tide tables | Tides Near Me | 159,744 | Free | 1 mo | 10/10 | 8/10 |

The head tide terms are owned by **free, 4.7–4.8★, actively-maintained apps**, one with
**159,744 ratings and updated last month**. Tide Charts is stale *and still #1* — staleness has
not dislodged it, and the rest of the field is healthy.

`autoaso.md` §0: *"If you're asked to optimize an app whose competitors are good and free, say
so — ASO won't rescue a bad market."* **Said.** Do not spend the name on "tide chart".

**What IS winnable** — same research, the long tail:

| Query | Results | Incumbent weakness | Verdict |
|---|---|---|---|
| **sight reduction** | only 73 | top 10 are *rifle-sight* apps (Leica, Nikon SpotOn 2.1★, Mil-Dot); the one nav app has **0 ratings** | wide open — Apple has nothing to serve |
| **celestial navigation** | 158 | EZ Celestial Nav $29.99/25 ratings/18 mo stale · Celestial Navigation $1.99/15 ratings/**71 mo** stale · Celestial Nav 10 ratings | genuinely weak |
| **magnetic declination** | 161 | CrowdMag 24 ratings · geoTools **102 mo** stale · MagVar 1 rating · WMM PAL 1 rating **2.0★** | no real incumbent |
| **tidal current** | 170 | Actual Currents 16 ratings · PredictCurrent 232 · Real Tides & Currents $6.99/497 | moderate |
| **slack water** | **15 total** | mostly irrelevant (GroupMe, Canva, Instagram); best match has 1 rating | no competition; volume unknown |

**Buy-once precedent is real** (paid tide apps that sell): AyeTides **$7.99 / 4,857 ratings**,
Tide Graph Pro $5.99 / 3,570, My Tide Times Pro $3.99 / 1,171, Real Tides & Currents $6.99 / 497,
World Tides 2026 $5.99. A paid tide app is not a doomed shape — a paid *head-term* tide app is.

Search volumes: **unknown**. Apple publishes them to nobody (`autoaso.md` §4). Nothing above is
a volume estimate; every figure is a live iTunes Search API reading, cached in
`marketing/.cache/` (gitignored, regenerable), script `marketing/aso_research.py`.

## Audit of the drafted fields

- **HEAD NOUN** — the target phrases here are not `<x> calculator` shaped; their head nouns are
  *navigation*, *reduction*, *declination*, *current*, *chart*. **The trap still applies**: the
  brand is "Marine **Nav**", and `Nav` is an abbreviation that will never match *navigation*.
  So **"Navigation" is spelled in full in the subtitle**, which is what makes both
  "marine navigation" and "celestial navigation" combinable at all.
- **Duplication** — none across name/subtitle/keywords, checked mechanically.
- **Unused characters** — name 28/30, subtitle 28/30, keywords 100/100.
- **Locales** — en-US primary + **es-MX** secondary (US-storefront indexed, ~160 free chars).
  es-MX is **self-sufficient**: keywords never combine across locales.
- **Promotional text** — not used as keyword space (zero ranking effect).
- **4.3(b)** — the differentiators (offline, NOAA-validated, no subscription) appear in the
  subtitle and in every screenshot caption, i.e. visible at review, not just true in the code.

Verify with `marketing/aso_check.py` — it re-derives coverage from the field strings.

## Proposed metadata

| Field | Value | Used |
|---|---|---|
| **Name** (en-US) | `Marine Nav: Tides & Currents` | 28/30 |
| **Subtitle** (en-US) | `Celestial Navigation Offline` | 28/30 |
| **Keywords** (en-US) | `sight,reduction,sextant,declination,magnetic,tidal,slack,water,chart,table,times,clock,almanac,coast` | 100/100 |
| **Name** (es-MX) | `Tide Current Navigation` | 23/30 |
| **Subtitle** (es-MX) | `Offline Tides Prediction` | 24/30 |
| **Keywords** (es-MX) | `marine,celestial,sextant,declination,magnetic,slack,water,clock,chart,table,tidal,almanac,nautical` | 98/100 |

No spaces after commas. No competitor trademarks. "NOAA" deliberately **excluded** from the
keyword fields — it is a US-government agency rather than a competitor mark, and precedent exists
("Tide Alert (NOAA)"), but it implies endorsement; **human decision**, not mine to make.

## Coverage check — every phrase complete inside ONE locale

| Target query | supplied by |
|---|---|
| tide chart / tide tables / offline tides / tidal currents / slack water / tide clock / marine navigation / celestial navigation / magnetic declination | en-US **and** es-MX |
| tide times | en-US |
| sight reduction | en-US |
| tide predictions | es-MX |
| nautical almanac | es-MX |

**Uncovered: none.**

## RECOMMENDATIONS

| # | Action | Bucket | Impact | Notes |
|---|---|---|---|---|
| 1 | **Do not target head tide terms.** Aim the listing at sight reduction / celestial nav / declination / currents | [AUTO] done | high | The 159k-rating free incumbent is not beatable with metadata |
| 2 | Ship the drafted name/subtitle/keywords with the first release | [MANUAL] | high | Metadata ships with a version; this is v1.0's free ride |
| 3 | Add the **es-MX** locale at first submission | [MANUAL] | med | ~160 free indexed chars; self-sufficient as drafted |
| 4 | Decide on "NOAA" in keywords | [MANUAL] | low | Endorsement-implication call |
| 5 | **Featuring Nomination** with the release | [MANUAL] | med | Free, story-judged, zero-ratings does not disqualify, ≥2 weeks lead |
| 6 | Run the §2 positional diagnostic 2–3 weeks post-launch and diff | [AUTO] later | high | The only way to learn whether any of this worked |
| 7 | `SKStoreReviewController` at moment of delight | [AUTO] | med | Not yet wired — the app has no review prompt |
| 8 | Competitor keyword extraction | [NO-DO] | — | Requires scraping; refused |

### ⭐ Highest-impact next action
Accept that this is a **long-tail celestial/currents/declination app that also does tides**, not a
tide-chart contender — and let the name and subtitle say so before a single character is submitted.

### 🙋 Human must do
Submit the metadata (App Review gated) · create the es-MX locale · decide on "NOAA" · seed the
first 20–50 real installs (sailing/cruising forums, r/sailing, SSCA — read each sidebar; Reddit's
90/10 rule is retired but per-subreddit rules govern) · file the Featuring Nomination.

### ⚠️ Re-verify next run
iTunes Search API positions (they move) · the US secondary-indexed locale list · whether Apple Ads
popularity data is still degraded · Tide Charts' staleness (a refresh would change the picture).
