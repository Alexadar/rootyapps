# BUILD PROMPT — portfolio store: fleet state + expiring metrics

**Start here.** Open this repo in Claude Code, enter **plan mode**, read this file top to bottom.
It assumes you know nothing about this repo.

**This is infrastructure, not an app.** It earns nothing directly. Its whole justification is that
it makes portfolio decisions answerable in seconds instead of an afternoon, and that it captures
data which is **currently expiring unrecovered**. Keep it small enough that it never competes with
shipping apps.

---

## 1. Where you are

`rootyapps`, a monorepo of ~20 standalone iOS/macOS apps by a solo developer. ~8 live on the App
Store. `marketing/` is a **SHARED** library every app calls in place.

```
rootyapps/
├── CLAUDE.md                          monorepo rules — read it
├── marketing/
│   ├── logic/                         ASC API client + fetchers — REUSE, never fork
│   │   ├── asc_client.py              auth + request(); creds from ENV only
│   │   ├── fetch_analytics_reports.py · fetch_reviews.py · fetch_sales_reports.py
│   │   ├── ads_client.py              Apple Ads (new, untracked)
│   │   └── upload_screenshots.py · upload_previews.py · update_metadata.py
│   ├── screenshots_generator/         store media pipeline — see §6
│   ├── autoaso.md                     §6.5 hard-won ASO rules, §6.6 multilingual pipeline
│   └── portfolio/                     ← you are here (empty)
└── docs/                              research + one-off analytics snapshots
```

⚠️ **`marketing/` is shared and must never be forked into an app folder.** Same rule applies to
what you build here. Every app reads this store in place.

---

## 2. What this is — and what it is not

**It is:** a local SQLite store of fleet state and longitudinal metrics, fed by daily collectors,
read by a CLI and by Claude sessions.

**It is not a CRM in the sales sense.** There are no contacts, deals, or pipeline. Do not build
them.

⚠️ **It is not a SaaS.** No hosted service, no web backend, no auth, no cloud database. Local file,
local scripts. The house default is a local tool using the owner's own keys.

⚠️ **It is READ-ONLY against App Store Connect.** This tool collects and reports. It must never
create a version, submit, change price, alter availability, or write metadata or media. Those are
the owner's decisions and are handled by the existing scripts. **Build no write path at all.**

---

## 3. ⚠️ Why this is urgent — measured, not assumed

Pulling Kerf Construction Calculator (app `6788179502`) on 2026-08-16, its **ONGOING** analytics
report request returned **16 instances, with DAILY instances spanning only 2026-08-04 → 08-15.**
Twelve days.

The request has existed far longer than twelve days. **Apple ages out daily report instances on a
rolling window.** The July numbers for this app survive only because someone once wrote them into
`docs/own_analytics_2026-07-29.md` by hand.

**Every day nobody collects is a day of funnel history that becomes permanently unrecoverable**,
across every live app.

**Your first action after the plan is approved is a backfill of everything still retrievable
today**, for every live app — before writing anything else. Verify the retention window yourself
and record what you find; do not trust this paragraph as a constant.

---

## 4. The ASC analytics API — four steps, and two traps that cost an afternoon

```
POST/GET /v1/apps/{id}/analyticsReportRequests        -> request  (ONGOING + ONE_TIME_SNAPSHOT)
GET      /v1/analyticsReportRequests/{id}/reports     -> report types, id = "r{N}-{requestId}"
GET      /v1/analyticsReports/{id}/instances          -> per granularity + processingDate
GET      /v1/analyticsReportInstances/{id}/segments   -> signed .gz URLs
```

**Trap 1.** `GET /v1/analyticsReports/{id}/segments` returns **404 PATH_ERROR "The relationship
'segments' does not exist"**. The `instances` step is not optional and is easy to skip.

**Trap 2.** The engagement TSV has **both** an `Event` column and an `Engagement Type` column.
Impressions and page views live in **`Event`**; `Engagement Type` is **blank**. Reading the
obvious-looking column silently yields zero for everything.

Known report ids (suffix the request uuid): `r14` App Store Discovery and Engagement Standard ·
`r3` App Downloads Standard · `r12` App Store Purchases Standard · `r6` Installation and Deletion.
Columns: `Date, App Name, App Apple Identifier, Event, Page Type, Source Type, Engagement Type,
Device, Platform Version, Territory, Counts, Unique Counts`.

⚠️ **A report with no data emits ZERO instances — not an empty file.** Absence of instances means
*measured zero*, and must be recorded as an explicit zero, not left as a gap. Confusing "no data
yet" with "no downloads" is the difference between a wrong conclusion and a right one.

---

## 5. Schema

Facts append-only; everything derived is a view. Design for idempotent re-collection — running the
collector twice for the same day must not double-count.

- **`app`** — folder, ASC app id, bundle id, name, live platforms, current live version per
  platform, lifecycle state, media-locale allowlist (§6)
- **`funnel_fact`** — app × date × territory × device × source_type × event → counts, unique counts.
  This is the core table.
- **`change_annotation`** — app, date, kind (`name` / `subtitle` / `keywords` / `screenshots` /
  `preview` / `price` / `availability` / `version` / `ads`), free text, and where known the git
  commit. **This is what turns a metric series into an experiment ledger.**
- **`review`** — app (own or competitor), rating, title, body, version, territory, date, first-seen
- **`keyword_observation`** — term, date, ordered hints, storefront
- **`store_state_snapshot`** — app × platform × version × locale → name, subtitle, keywords, price,
  availability, category, age rating, captured at
- **`store_media`** — §6
- **`ad_spend`** — campaign, app, date, spend, impressions, taps, installs

⚠️ **Paid and organic must be separable.** Apple Ads Basic started on **2026-08-06** for Storypole
and Marine Nav at $50/mo each. Analytics after that date mix organic and paid for those two apps.
If the funnel table cannot separate them, every conclusion drawn from it after 2026-08-06 is
confounded. Carry the dimension from day one.

---

## 6. Store media provenance — the rule that has no guard

`marketing/screenshots_generator/README.md` names three ways it silently ships the wrong thing. Two
have real code guards: stale files (`collect_captures()`, `purge_stale_outputs()`) and tofu
(`font_covers()`, `load_or_get_font()`). The third has none:

> **A screenshot freezes the build it was taken from. Re-capture after ANY string or UI change.**

The generator cannot enforce this — it only sees pixels. It cannot know what version the app was at
capture time, nor what is live on the store now. That is cross-system state, and it is the reason
this store exists.

**Two pieces of work:**

1. **Stamp provenance at capture.** Write a sidecar manifest beside each capture run recording
   app · locale · platform · `MARKETING_VERSION` · git commit · device or simulator + OS ·
   timestamp. Same discipline as the licence stamping in `aisixteen.models/scripts/`: the fact
   travels with the artifact instead of living in someone's memory.

2. **`store_media` table + staleness check.** One row per app × locale × platform × size, joining
   local capture provenance against what ASC actually holds (screenshot id, upload date, attached
   version). The check is one query: **live version > version the media was captured from →
   stale listing.**

⚠️ **Media locales are a deliberate subset of text locales, not a gap.** Ephemeris ships 17
languages of metadata but store media in only `ja` / `de-DE` / `fr-FR`, with `uk` excluded on
purpose. Without a per-app media-locale allowlist this check reports phantom missing media forever
and gets ignored — which is how a real alarm dies.

Layout to read (do not change it):
```
<app>/marketing/raw/<loc>/<platform>/NN_<name>.png     captures
<app>/marketing/aso/<loc>/<platform>/params.yaml       caption texts
<app>/marketing/aso/<loc>/<platform>/<W>x<H>/          framed, store-ready
```
`<loc>` is the SHORT code; ASC wants `en-US` / `de-DE` / `no`. **There is exactly one mapping dict,
in the uploader. Never create a second.**

### Why this is on the critical path right now

Kerf's failing funnel step is **page view → download** (712 impressions → 54 page views → 0
downloads over 12 days). Screenshots are the largest lever on that step. Before anyone concludes
"$9.99 does not convert," the media on that page must be known to reflect the shipped build.
Otherwise a viable price gets killed on evidence from a stale listing.

---

## 7. Conformance checks — state drift is the failure this catches

Five apps were once silently **removed from sale** because territory availability was unset and
nobody was watching. That is the class of bug this exists for.

Nightly, for every live app, assert and report: territory availability set · subtitle non-empty ·
keywords present and ≤ 100 chars · category set · age rating set · `PRODUCT_NAME` contains no
"Swift" (App Review 5.2.5 has caused a real rejection here) · store media not stale (§6) · media
present for every locale in that app's allowlist.

**Report drift. Never fix it.** Every one of those fields is an owner decision.

---

## 8. Read path

- **CLI**, at minimum: `funnel <app> --since <date>` · `compare <app> <window-a> <window-b>` ·
  `drift` · `reviews <app> --since` · `timeline <app>` (annotations overlaid on the funnel).
- **MCP server** over the same SQLite, read-only. A dozen Claude sessions run against this repo
  concurrently and currently re-derive portfolio state from scratch each time — the four-step
  analytics chain above was rediscovered by trial and error in a session that had the answer in a
  memory file. Exposing the store over MCP is what stops that.

Output must be terse and numeric — root cause, numbers, options. No narrative.

---

## 9. Credentials

Read from the environment only, exactly as `asc_client.py` already does:
`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH`, and `ADS_*` for Apple Ads.

⚠️ **`keys/` is gitignored and `.env` is gitignored. Never print, log, or commit key material,
and never hard-code an issuer id or key path** — two existing scripts do hard-code them, and that
is the pattern to move away from, not copy.

The SQLite file and any downloaded segments are data, not source. Keep them out of git.

---

## 10. Tests

Unit tests, executed — they must pass before you report done.

Cover: the `Event` vs `Engagement Type` column trap (a fixture where the wrong column would yield
zero) · zero-instances-means-measured-zero, distinct from not-yet-collected · idempotent
re-collection of the same day · paid/organic separation across the 2026-08-06 boundary · media
staleness true **and** false · the media-locale allowlist suppressing phantom gaps · date-window
comparison arithmetic.

House rule: **test the state space** — every toggle both directions. A dead toggle shipped here
once because tests only ever saw default state. Guards must be **negatively verified**: break each
one deliberately, with inputs shaped unlike the ones you thought of, and prove it fails.

---

## 11. 🛑 Stop and ask

Anything that writes to App Store Connect · scheduling (launchd vs cron) · adding a dependency
beyond what `marketing/logic` already uses · anything that would fork rather than reuse
`asc_client.py` · a dashboard or any UI beyond the CLI.

---

## 12. Deliver a plan first

The schema with the paid/organic dimension and how re-collection stays idempotent · the retention
window you actually measured and the backfill plan · where capture provenance gets stamped and what
in `screenshots_generator` must change to stamp it · the conformance check list · the CLI surface ·
whether the MCP server is in this run or the next · the test matrix · the §11 questions.

**Backfill first, then build.** The data is expiring while the plan is being written.
