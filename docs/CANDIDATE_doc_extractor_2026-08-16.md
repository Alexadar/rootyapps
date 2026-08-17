# CANDIDATE — on-device document extractor w/ webhook output — autoaso pass, 2026-08-16

Requested by `fantastic_canvas`. **Draft and stage only.** Method: Apple autocomplete
(`MZSearchHints`, US storefront `143441-1,29`) + iTunes Search API, plus the existing measurement in
`docs/CANDIDATE_scanner_2026-08-06.md` (282 apps, 60+ terms, measured 10 days ago).

**Verdict: do not ship as a separate app. This is GridScan's Mac version, or a feature set inside
GridScan. The automation positioning it is built on measures zero in App Store search, and as a
second document-extraction app on the same developer account it creates the 4.3 exposure the brief
claims it avoids.**

---

## 1. The blocking problem: GridScan already exists and already ships this

`gridscan/` is built. From `gridscan/PROMPT.md`:

> On-device table/document extraction · verification · **clean CSV/XLSX export** ·
> **$9.99 paid upfront** · iPhone + iPad, iOS/iPadOS 26+ · *"flags anything that doesn't add up
> before export"*

The proposed app: on-device OCR + extraction · review queue with approve/reject · export to
webhook / Airtable / Notion / CSV · audit trail · macOS.

Both are **on-device document → structured data → human verification → export.** The differences are
platform, destination list, and schema proposal. That is a feature delta, not a different product.

⚠️ **The brief's claim "4.3 risk none (single app)" is incorrect.** Guideline 4.3 is evaluated
against the developer's catalog, not against one submission in isolation. Two apps from one account
that both scan documents on-device and emit structured data is the pattern 4.3 exists for. The
AISixteen trilogy manages this only because the UI grammars genuinely diverge; "same job, different
export destinations" does not.

---

## 2. The positioning vocabulary does not exist in search

The brief asks whether the automation angle carries demand. Measured — it does not:

| Term | Hints |
|---|---|
| `document parser` | **0** |
| `receipt to spreadsheet` | **0** |
| `invoice to csv` | **0** |
| `ocr to excel` | **0** |
| `extract data from pdf` | **0** |
| `form data extraction` | **0** |
| `pdf to json` | **0** |
| `purchase order scanner` | **0** |
| `invoice data entry` | **0** |
| `bookkeeping automation` | **0** |
| `pdf to csv` | 4 — `pdf to csv`, `pdf to csv converter` generic; 2 titles |

Already measured 2026-08-06 and unchanged: `pdf data extraction` → **0**, `extract table from pdf`
→ **0**, `receipt to excel` → **0**, `scan table to csv` → **0**, `photo to spreadsheet` → **0**.

The destination brands are brand queries, i.e. the CRM trap — capturing them needs someone else's
trademark in the name:

```
'zapier'   -> zapier · zapier ai · zapier inc.
'airtable' -> airtable · airtable.com · airkit: supercharge airtable!
'notion'   -> notion · notion calendar · notion: notes, tasks, ai ...
'n8n'      -> n8n · n8n.io · n8n hub · n8n manager · n8n triage ...  (all titles)
'webhook'  -> 10 hits, ALL app titles — webhookbeam · webhook catcher · webhookpush ...
```

`webhook` and `n8n` are developer-tool queries answered by tiny monitoring utilities. Neither is a
document query, and neither is a buyer looking for extraction.

**This is the same conclusion the scanner doc already reached:** *"The niche vocabulary does not
exist in search. We rank on `document scanner` / `pdf ocr` / `receipt scanner` and differentiate on
tables — never the reverse."* The proposed app inverts exactly that rule — it leads with the
vocabulary that measures zero.

---

## 3. Paid-once precedent: proven, and GridScan already holds the position

The brief asks for store-side price precedent. It exists, and it is the strongest measured in this
cycle:

| App | Price | Ratings |
|---|---|---|
| **TurboScan Pro** | **$9.99** | **295,340** |
| Clear Scan | $19.99 | 17,705 |
| JotNot Pro | $6.99 | 30,200 |

**Answer to the brief's question 2:** the *category* is a genuine paid-once store product — unlike
the CRM and ASO candidates, which measured revenue-zero. But that precedent attaches to
`document scanner` / `pdf ocr` / `receipt scanner`, which is the ground GridScan is already
targeting at $9.99. A second app cannot inherit it by pointing at webhooks.

---

## 4. Three things in the description that need correcting

**a) "low-confidence fields flagged for your eyes first" — not computable as described.**
Vision's `VNRecognizedText` exposes a real `confidence`. Foundation Models structured output
(`@Generable`) does **not** expose per-field extraction confidence. So confidence can be honest at
the OCR layer and is unavailable at the extraction layer. Shipping a "low confidence" badge derived
from anything else is invented data. Either flag only OCR confidence and say so, or replace the
claim with something measurable (field missing, failed a format/validation rule, disagrees with a
computed total).

**b) The schema-proposal step is the highest hallucination surface in the product.** An LLM
proposing field *names* is fine and reviewable. An LLM extracting field *values* can fabricate a
plausible number that survives review because it looks right. The reconciliation idea already in
GridScan — check the arithmetic, show the delta — is the only real defence and should be mandatory
here, not optional.

**c) The device gate is a cold-start problem, not a footnote.** "Requires Apple Silicon with Apple
Intelligence" means the app does nothing on ineligible hardware. On a paid-upfront app that is a
refund-and-one-star path. It belongs in the subtitle-adjacent copy and the first screenshot, not the
last bullet.

Not flagged as problems: on-device processing, no account/server, Keychain custody of user-supplied
destination tokens, "nothing exports without your tap", and the `Data Not Collected` label — all
accurate as written, given webhook destinations are user-configured and the app never phones home.

---

## 5. What the good idea in here actually is

Two things in the brief are genuinely new relative to GridScan and worth keeping:

1. **macOS.** The 2026-08-06 measurement found *"macOS is markedly emptier"* in this category.
   That is a real, unexploited gap.
2. **Destinations beyond a file.** Webhook / Airtable / Notion is a legitimate capability — it just
   cannot be the *discovery* story, because nobody searches for it.

Both fit inside GridScan rather than beside it: **GridScan for Mac, ranking on the proven scanner
vocabulary, with automation destinations as a differentiating feature on the product page.** One
app record, no 4.3 exposure, and it inherits the $9.99 precedent instead of trying to build a new
one on zero-volume terms.

---

## 6. RECOMMENDATIONS

| # | Recommendation | Basis |
|---|---|---|
| 1 | **Do not ship as a separate app.** Make it GridScan's Mac target or a GridScan feature. | Same job as a built app on the same account; 4.3 catalog risk |
| 2 | **Never lead with parser/extraction/webhook vocabulary.** | 10 of 11 measured terms return zero hits |
| 3 | **Rank on `document scanner` / `pdf ocr` / `receipt scanner`; differentiate on destinations.** | Where the 295k-rating paid precedent lives |
| 4 | **Keep macOS — it is the real gap.** | "macOS is markedly emptier", measured 2026-08-06 |
| 5 | **Drop or redefine the confidence badge.** | FM gives no per-field confidence; claiming it is invented data |
| 6 | **Make reconciliation mandatory, not optional.** | Only defence against a plausible fabricated value passing review |
| 7 | **Put the Apple Intelligence hardware requirement in the store copy and first screenshot.** | Paid-upfront + non-functional device = refunds and 1★ |
| 8 | **Verdict on artifact-vs-product: genuine product — but as GridScan, not as a second app.** | Category has proven paid-once demand; this positioning does not |

---

## 6a. v2 decision — local RAG over the extracted archive

Decided by Oleksandr's session, 2026-08-16. Recorded here because it changes the storage design, not
just the feature list.

**Ships as a v2 product-page differentiator, never as a discovery story.** Measured 2026-08-16:

| Term | Hints |
|---|---|
| `ask your documents` · `ask my documents` · `search my documents` | **0** |
| `document search` · `find in scanned documents` | **0** |
| `search receipts` · `search invoices` | **0** |
| `semantic search` | 1, a company name |
| `rag` | `ragdoll` · `ragdoll games` · `ragdoll archer` — **hijacked**, same as `aso`→ASOS |
| `chat with pdf` | 10 hits, **all app titles** — chatpdf ×3, docmind, nottechat, parsleypdf, pdfchat |
| `pdf search` | 3 — `pdf search`, `pdf search pro`, `pdf search kit` |

So: rank on scanner vocabulary, differentiate on retrieval. **Stay out of `chat with pdf`** — it is a
saturated pile of ChatPDF clones and the wrong buyer.

### Storage design

- **Text chunks + extraction records sync via CloudKit private database** (SwiftData + CloudKit) —
  the user's own iCloud, no developer server, consistent with `Data Not Collected`.
- **Vectors never sync.** They are a device-local derived cache, re-embedded per device
  (`NLContextualEmbedding` + SQLite brute-force cosine). Reason: embedding-model versions drift
  across OS releases, so vectors computed on one OS silently degrade when read by another. Syncing
  them would produce retrieval that gets quietly worse and never errors.
- **FM answers must cite and display the retrieved source snippet. Retrieval-only is the honest
  default** — answer generation is opt-in on top of it.

### ⚠️ Two corrections to fold in

**a) It does not replace GridScan's existing search — the two must be scoped apart.** GridScan 1.0
already ships `CSUserQuery` semantic search over the library and plans `SpotlightSearchTool` for 1.1
(`gridscan/PROMPT.md` §9a). They are complementary and must not be built twice or collide in the UI:

| | Job |
|---|---|
| `CSUserQuery` / Spotlight | find the **document** — Apple-managed index, free, already in 1.0 |
| Local embeddings | retrieve the **passage** to cite — chunk-level, which Spotlight does not give |

**b) Do not claim end-to-end encryption in store copy.** CloudKit private database is encrypted in
transit and at rest, but **Apple holds the keys unless the user has Advanced Data Protection
enabled.** "The user's own iCloud, no developer server" is true and sufficient. "End-to-end
encrypted" is only true conditionally, and stating it unconditionally is invented assurance — the
same doctrine that killed the extraction-confidence badge in §4a.

---

## 7. Not measured

Non-US storefronts; whether the existing Mac scanner field has a rot pattern worth a separate read
(the 2026-08-06 sweep noted emptiness but did not rank Mac incumbents); and Airtable/Notion API
terms for third-party token use — a contract question, not a measurement.
