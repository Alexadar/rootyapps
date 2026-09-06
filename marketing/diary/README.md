# Marketing diary

One file per major market-action day. Each records **what was done · what was observed · the
effect (or "pending, read on DATE")**, at per-app granularity plus a portfolio summary.

## Why this exists
To measure whether ASO/territory/pricing changes actually move sales — not to assume they did.
Every entry captures the **pre-change baseline metrics** so a later re-snapshot can compute the
delta. Without the baseline written down the day of the change, the effect is unrecoverable
(Apple ages daily analytics out on a ~12-day rolling window — see the analytics memories).

## Hard-won measurement rules (do not relearn)
- **Page→purchase baseline is ~0.79–0.96%**, not 11.8%. A zero-sales result on <~100 page views is
  a sample-size artifact, NOT a broken page. Impression VOLUME is the binding constraint.
- **Never sum raw analytics instances** — DAILY instances are 3-day rolling windows that overlap;
  dedup by data-date (latest processingDate wins) or you inflate ~2.3×.
- **Ratings are not a sales proxy** (Ephemeris: 0 ratings, ~13 sales).
- **A metadata change needs review clearance + ~2 weeks** before its funnel is readable.
- **Attribution is only clean if the binary is byte-identical to the prior version** (Overtone, Par
  did this; Earth Around's build also changed code, so its funnel read is confounded).
- Apps in an Apple Ads campaign (Storypole, Marine Nav since 2026-08-06) have paid+organic mixed.

## Index
- `2026-08-08.md` — Kerf 1.0.3 ASO overhaul (the first big lever)
- `2026-08-16.md` — Kerf measured 58× impressions; portfolio findings; impression-wall correction
- `2026-09-06.md` — portfolio-wide funnel pull; double-count fix; 0.79% baseline; Ephemeris confirmed selling
- `2026-09-07.md` — execution day: 5 ASO submissions, 3 territory opens, AirCore analytics — **the cohort we are now tracking**

## Next read-back
~2026-09-21 (≈2 weeks after the 09-07 submissions clear review): first readable funnel deltas.
