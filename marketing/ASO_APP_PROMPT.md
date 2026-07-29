# GENERIC ASO AUDIT + REWORK PROMPT — run this per app

> **Fill in the one line below, paste this whole file into a fresh Claude Code session.**
> Working directory = the `rootyapps` repo root.

```
APP: <app folder, e.g. kerfcalc.swift>   APP STORE ID: <e.g. 6788179502>   STOREFRONT: US
TARGET QUERIES: <8-12 phrases a real buyer would type, e.g. "rafter calculator", "stair calculator">
```

---

## 0. Read first — these govern

1. **`marketing/autoaso.md`** — the ASO policy. **§6 (facts) and §6.5 (hard-won rules) are binding.**
2. `docs/distribution_2026-07-26.md` — what's verified about ranking, ratings, featuring, AEO.
3. The app's own `marketing/metadata.md` if it exists (the *draft* — may differ from what actually shipped).

**Non-negotiables:** ToS-clean only (no scraping, no grey-market keyword data). Never fabricate a number —
"unknown" is an acceptable answer. **You draft; the human submits.** Stop at the submit boundary.

## 1. Pull the LIVE metadata — never trust the local draft

The MCP App Store Connect wrapper **fails on collection GETs** (`appStoreVersions`,
`appStoreVersionLocalizations` return "does not allow GET_COLLECTION"). Use the raw API. This exact
pattern is known-working:

```python
# run with: marketing/venv/bin/python3
import json, time
from urllib.request import Request, urlopen
import jwt
KEY_ID="55B6L3J65N"; ISSUER_ID="057ddafb-cb0e-4410-9e0a-00e24f6e1688"
P8="/Users/oleksandr/Projects/rootyapps/keys/AuthKey_55B6L3J65N.p8.txt"
tok = jwt.encode({"iss":ISSUER_ID,"exp":int(time.time())+1200,"aud":"appstoreconnect-v1"},
                 open(P8).read(), algorithm="ES256", headers={"alg":"ES256","kid":KEY_ID,"typ":"JWT"})
def get(path):
    r=Request("https://api.appstoreconnect.apple.com/v1/"+path, headers={"Authorization":f"Bearer {tok}"})
    return json.loads(urlopen(r, timeout=30).read())

# versions:      get(f"apps/{APP_ID}/appStoreVersions")
# keywords etc:  get(f"appStoreVersions/{VERSION_ID}/appStoreVersionLocalizations")
# name/subtitle: get(f"appInfos/{INFO_ID}/appInfoLocalizations")   # via get(f"apps/{APP_ID}/appInfos")
```

**Where the fields actually live** (a common trap):
| Field | Endpoint |
|---|---|
| keywords, description, promotionalText, whatsNew | `appStoreVersionLocalizations` |
| **name, subtitle** | `appInfoLocalizations` |

Record, per platform and per version state (READY_FOR_SALE / PREPARE_FOR_SUBMISSION / IN_REVIEW):
name, subtitle, keywords (+ character counts), and **which locales exist**.

## 2. Run the positional diagnostic BEFORE writing any copy

For each TARGET QUERY:
```
https://itunes.apple.com/search?term=<q>&media=software&entity=software&country=US&limit=200
```
Throttle ≥3.5 s, cache. Report the app's index as `#N` or **NOT FOUND**, plus the #1 result.

This separates **"not indexed for this phrase"** (metadata bug — fixable now) from **"indexed but
outranked"** (popularity problem — metadata won't fix it). They need completely different responses.
Note honestly that this index is a *proxy for*, not identical to, in-app App Store search.

## 3. Audit — check every one of these

- [ ] **HEAD NOUN present?** Take the head noun of the target queries (calculator / tracker / planner /
      scanner / converter). Is it spelled **in full** as an atom in some indexed field **of that locale**?
      **An abbreviation in the app name does NOT count** — "Calc" never matches "calculator". This single
      check explained a live app being absent from all 8 of its target terms.
- [ ] **Duplication** — any word appearing in two of {name, subtitle, keywords}? Count the wasted characters.
- [ ] **Unused characters** — name of 30, subtitle of 30, keywords of 100. Report each as `used/limit`.
- [ ] **Locales** — does any secondary locale exist? For the US storefront, Spanish (Mexico) metadata is
      also indexed → ~100 free extra keyword characters, currently likely unused.
- [ ] **Combination check** — for each target phrase, confirm every word of it exists **within a single
      locale**. Keywords combine across name+subtitle+keywords but **never across locales**.
- [ ] **Wasted words** — "app", the category name, stop-words, plurals of included singulars: all free
      or auto-handled. Don't spend characters on them.
- [ ] **Promotional text used as keywords?** It has **zero ranking effect** — conversion copy only.
- [ ] **4.3(b)** — is the differentiator (validated math / offline / no subscription) actually *visible*
      in the name, subtitle or description? True-in-the-code doesn't count at review.

## 4. Research the target terms (ToS-clean)

For each target query, profile the ranking incumbents via the iTunes Search API: `userRatingCount`,
`averageUserRating`, `formattedPrice`, `currentVersionReleaseDate`. Look for the pattern that makes a
term winnable — **abandoned (>18 mo stale), low-rated, or subscription-priced with buy-once backlash**
(pull the Customer Reviews RSS for dated grievance quotes). Prefer **narrow, high-intent long-tail**
terms where relevance can beat popularity; do not chase head terms a 39k-rating incumbent owns.
Mark unknown volumes "unknown" — Apple publishes search volume to nobody.

## 5. Draft the new field set

Produce, ready to paste:
- **Name** (≤30) — brand + head noun if the human accepts it; otherwise brand only, and the head noun
  moves to the subtitle. State the trade-off explicitly; **the name is the heaviest-weighted field.**
- **Subtitle** (≤30) — must not repeat name words.
- **Keywords** (≤100) — comma-separated, **no spaces after commas**, atoms not phrases, zero overlap
  with name/subtitle.
- **Secondary locale (es-MX for US)** — English words, and **self-sufficient**: it must contain its own
  head noun, since combination does not cross locales.
- Show a **character count** for every field and a **before → after** diff.
- List, per target query, which fields now supply each word of the phrase.

## 6. Hand-off (stop here)

Output the §9 RECOMMENDATIONS table from `autoaso.md`, plus:
- **Which version to put this in.** Metadata changes ship with a version; if one is already staged in
  `PREPARE_FOR_SUBMISSION`, that's the free vehicle — say so.
- **Featuring Nomination** — if a release is queued, draft the story pitch. Free, story-driven, no
  traffic prerequisite, ≥2 weeks lead (~2 months ideal).
- **Re-run the §2 diagnostic 2–3 weeks after the change** and diff the positions. That's the only way to
  learn whether any of this worked.

**Do not** submit, do not change price, do not create a version, do not touch a live listing without
explicit human approval. Draft, stage, hand off.

## 7. Required output

```
## ASO AUDIT — <app> — <date>

### Live metadata (from ASC API)
| Field | Value | Used |
### Positional diagnostic
| Query | Position | #1 result |
### Audit findings
- head noun: present/ABSENT (which field)
- duplication: <words>, <n> chars wasted
- unused: name x/30, subtitle x/30, keywords x/100
- locales: <list>
### Proposed metadata (before → after, with char counts)
### Coverage check
| Target query | words supplied by |
### RECOMMENDATIONS
| # | Action | [AUTO]/[MANUAL] | Impact |
### ⭐ Highest-impact next action
### 🙋 Human must do
```
