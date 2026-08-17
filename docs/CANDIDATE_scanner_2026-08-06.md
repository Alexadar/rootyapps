# Candidate — verified table/document scanner (working title TBD)

> Measured 2026-08-05/06 via the ToS-clean N3 method: Apple autocomplete (`MZSearchHints`, US
> storefront header), iTunes Search API, Customer Reviews RSS. 282 distinct apps scanned across
> 60+ query terms. Nothing scraped, nothing inferred where it could be measured.

---

## 1. Verdict

**Build it.** This is the first niche measured in this cycle that clears every gate:

- **Paid-upfront is proven at our price point** — TurboScan Pro, **$9.99, 295,340 ratings**, healthy
- **Three incumbents are actively betraying paid users** with subscription conversions
- **The top unmet need is structured export**, which is exactly what our stack produces
- **One direct competitor exists**, three weeks old, zero traction, priced as a subscription
- **Apple ships the hard technology free** in iOS 26 — the moat is product, not engineering

The reason to build is now entirely the **business position**, not the technology. That is a
weaker moat than usual and must be stated plainly — see §8.

---

## 2. Demand — measured

Strong, generic, and unowned by a single brand:

| Term | Autocomplete hits | Generic (non-title) |
|---|---|---|
| `document scanner` | 10 | **9** |
| `pdf ocr` | 10 | **9** |
| `receipt scanner` | 10 | **8** |
| `business card scanner` | 10 | **8** |
| `pdf to excel` | 10 | 6 |
| `invoice scanner` | 6 | 6 |
| `handwriting to text` | 10 | 6 |
| `inventory scanner` | 10 | 6 |
| `offline scanner` | 7 | 3 |

Terms that returned **zero** — do not target them, they generate no impressions:
`scan table to csv`, `photo to spreadsheet`, `receipt to excel`, `bank statement scanner`,
`extract table from pdf`, `pdf data extraction`, `private document scanner`, `ocr no internet`,
`spreadsheet scanner`.

> **The niche vocabulary does not exist in search.** We rank on `document scanner` / `pdf ocr` /
> `receipt scanner` and differentiate on tables — never the reverse.

---

## 3. The free-giant gate is overridden here — deliberately

Free giants are enormous: 7,501,186 (receipt), 1,859,777 (document scanner), 1,575,001 (OCR),
1,860,493 (CamScanner), 1,393,269 (iScanner).

By our standing rule that is a kill. **It is overridden by direct evidence**, and the reasoning is
recorded so it is not re-litigated:

The free-giant gate is a *proxy* for "nobody needs to pay." Here we can measure the thing itself —
paid apps coexist with those giants at scale:

| App | Price | Ratings | Recent avg | Negative |
|---|---|---|---|---|
| **TurboScan Pro** | **$9.99** | **295,340** | 4.75★ | 7% |
| Clear Scan | $19.99 | 17,705 | 4.56★ | 11% |
| JotNot Scanner Pro | $6.99 | 30,200 | 4.61★ | 9% |
| ScanBizCards | $0.99 | 13,763 | 4.69★ | 8% |

Measured coexistence beats the heuristic. Document scanning is a **work tool** — repeated use,
output matters, ads are intolerable in a professional context.

---

## 4. The wound — subscription betrayal, quantified

Customer Reviews RSS, most-recent pages, ~200–250 reviews per app.

| App | Lifetime | **Recent** | 1–3★ share | Subscription mentions |
|---|---|---|---|---|
| **SwiftScan AI** | 4.76★ | **2.35★** | **72%** | **94 of 249** |
| Scanner Pro | 4.87★ | 4.31★ | 19% | 24 (20 in negatives) |
| Genius Scan | 4.90★ | 4.66★ | 9% | 12 (7 in negatives) |
| TurboScan | 4.91★ | 4.75★ | 7% | 2 |
| Clear Scan | 4.77★ | 4.56★ | 11% | 2 |

Verbatim:

> *"Customer Basic Lifetime NOT true"* — Genius Scan
> *"What did I pay lifetime fee for?! I paid for GS+ and now you have upstage to Ultra?! For a
> yearly fee?"* — Genius Scan
> *"Was the Best, but Now - junk! Money grubbing, developers! This used to be the very best
> scanning app available and I purchased it years ago."* — Scanner Pro
> *"Added when it was free now they want me to pay for 'pro.'"* — JotNot

**The apps that stayed paid-upfront are the happiest cohort in the category.** This is the
`premium-price-needs-...`/monetization principle exactly: buy-once is a weapon precisely where
rivals took money and then moved to subscription.

---

## 5. The unmet need — export

`export` was the **top theme in nearly every app's recent reviews** (25, 24, 24, 21, 18, 15).

> *"the feature I need most is no longer available? Export to CSV/Excel"* — ScanBizCards
> *"No longer supports email function?"* — Clear Scan, 7-year user
> *"latest updates removed the option to maintain the same page size"* — Scanner Pro
> *"can't do multiple photos from my gallery"* — TurboScan
> *"2 YEARS OF SCANS"* lost — TurboScan

Also notable: `table` appears in only **20 of 282** app descriptions, and **exactly one of those is
paid**.

**Everyone scans acceptably. Nobody gets structured data back out cleanly.**

---

## 6. Competition — one direct competitor, three weeks old

**`Tabular: Scan Tables to CSV`** — id 6767537740

| | |
|---|---|
| Released | **2026-07-14** (updated 07-16, v2) |
| Developer | solo indie |
| Size / min OS | 6 MB / **iOS 26.0** |
| Ratings | **0** |
| Monetization | **$1.99/month or $13.99/year**, export paywalled |

Its description is our product almost verbatim: on-device table recognition via Vision, inline cell
editing, manual grid adjustment, CSV/XLSX export, no account, no network.

**It made the one mistake this market punishes**: a subscription to export your own scanned table,
in a category where SwiftScan sits at 2.35★ over exactly that.

**Do not read its 0 ratings as absence of demand.** It is three weeks old with no ASO — that is the
impressions wall, not a market verdict.

### Nobody has adopted the new APIs

**2 of 282 apps require iOS 26+.** Tabular, and a 1-rating "Scan Master."

The 63 new entrants since WWDC25 are generic free "PDF Scanner" clones from offshore shell
companies — none above 1,806 ratings, most under 100. Flooding, not competition. **This raises our
own 4.3 exposure if we ship a generic scanner** — the differentiated framing is a review argument,
not only a marketing one.

### macOS is markedly emptier

| Mac query | Results | Top free | Paid present |
|---|---|---|---|
| `ocr` | 19 | **112 ratings** | TextSniper $9.99, PDFScanner $24.99 |
| `receipt scanner` | 18 | 1,794 | Microbooks $12.99 |
| `pdf scanner` | 18 | 50,747 | PDFScanner $24.99 |

Mac has a fraction of the competition and higher prices hold. Universal is our pattern anyway;
here it is also the softer target.

---

## 7. Function list — Apple vs ours

> Requested explicitly: what the SDK gives vs what we build. **Latest SDK assumed; iOS 26+ is
> acceptable as the primary target, with §7.4 covering the fallback decision.**

Legend: **A** = Apple ships it, we call it · **O** = ours to build · **A+O** = Apple provides the
primitive, the product work is ours.

### 7.1 Extraction — almost entirely Apple

| Function | Who | Mechanism |
|---|---|---|
| Table → 2D cells, addressable by row/column | **A** | `RecognizeDocumentsRequest` → `DocumentObservation.Container.Table` |
| Spanning cells (merged) | **A** | cell `row`/`column` as ranges |
| Nested content inside a cell | **A** | cell `.content` is a full container |
| Lists, paragraphs, lines, words, transcript | **A** | `Container.Text` |
| Natural reading order | **A** | paragraph grouping |
| Emails · phones · postal addresses · URLs | **A** | `detectedData` |
| **Dollar amounts with currency** | **A** | `detectedData` |
| **Measurements with units** | **A** | `detectedData` |
| Dates/times as calendar events | **A** | `detectedData` |
| Tracking numbers, flight numbers, payment ids | **A** | `detectedData` |
| Barcodes / QR in-document | **A** | `BarcodeReaderTool()` |
| 26 languages | **A** | built in |
| Interactive re-segmentation (tap/box/lasso, iterative) | **A** | `GenerateIterativeSegmentationRequest` — ⚠️ **WWDC26 = next OS, in beta now. NOT in 1.0.** |
| Image quality / smudge scoring | **A** | `CalculateImageAestheticScoresRequest` + smudge |
| On-demand model download (keeps binary small) | **A** | `downloadAssets()` / `assetStatus` |

**Consequence: 1.0 is pure Apple SDK. We ship no model weights at all.**

- **No 152 MB payload** — the whole app should land in single-digit MB (Tabular does it in 6 MB)
- **Nothing to maintain** as Apple improves the models underneath us
- **No licence question.** Worth being precise, because the earlier draft of this doc was sloppy:
  SAM2 is Apache 2.0 and fine, but the **FastVLM and MobileCLIP research weights ship under
  Apple's ML Research licence, whose commercial terms would need verifying before shipping them
  in a paid app**. Calling the SDK API instead sidesteps the question entirely — that is
  `PRINCIPLES_ondevice_ml.md` §2 (verify the weights file, not the repo) resolved by not
  redistributing weights at all.

Third-party models re-enter **only** if §7.4 option 2 is chosen — and that choice should be made
on market reach, not on capability, since the SDK covers the capability.

### 7.2 The differentiator — verification (ours)

**Tables carry their own oracle: arithmetic.**

| Function | Who | Note |
|---|---|---|
| **Column totals reconcile to a totals row** | **O** | the core claim |
| **Receipt: line items + tax = stated total** | **A+O** | amounts parsed by Apple; the check is ours |
| **Running-balance reconciliation** (statements) | **O** | each row must follow from the last |
| **Per-cell confidence surfacing + review queue** | **A+O** | Apple gives confidence; the UX is ours |
| **Column type inference** (number/date/currency/text) | **O** | with parse failures surfaced, not silently mangled |
| **"Verified" vs "unverified" export state** | **O** | the thing worth paying for |

No competitor checks whether its own output is arithmetically consistent. This is the oracle-first
pattern applied to OCR, and it is the single strongest reason to choose us over free CamScanner.

### 7.3 Workflow — ours, and where the money is

Per `PRINCIPLES_ondevice_ml.md` §5: the money sits in the part that needs no model.

| Function | Who | Complaint it answers |
|---|---|---|
| **Multi-page table stitching** | **O** | Apple returns *one observation per image*; joining pages, dropping repeated headers, aligning columns is entirely ours — and it is what real scanning is |
| Batch import from Photos | **O** | *"can't do multiple photos from my gallery"* |
| Consistent page size across pages | **O** | *"removed the option to maintain the same page size"* |
| Export-everything / local backup | **O** | *"2 YEARS OF SCANS"* lost |
| Reliable email/share/Files export | **O** | *"No longer supports email function?"* |
| Naming templates (date/vendor/type) | **O** | recurring organisation ask |
| Shortcuts actions | **A+O** | App Intents; nobody in the category offers automation |
| CSV/XLSX writer | **O** | must open cleanly in Excel, Numbers, Sheets |
| vCard export (business cards) | **A+O** | ScanBizCards' explicit regression |

### 7.4 Apple Intelligence + Siri — the standout addition

Verified against WWDC26 session 240. **Free, on-device, no per-use cost — compatible with buy-once.**

| Function | Who | Mechanism |
|---|---|---|
| **In-app Q&A over a scanned document** | **A** | Foundation Models framework, text in → answer out |
| Image input to the model | **A** | Foundation Models multimodal (WWDC26) |
| **Siri semantic search across your scans** | **A+O** | `@AppEntity(schema:)` + `IndexedEntity` + `@Property(indexingKey:)` |
| **Onscreen awareness — "what's the total on this?"** | **A+O** | `NSUserActivity` (single item) or `.appEntityIdentifier()` view annotations (lists) |
| Summarise / extract on demand | **A** | Foundation Models guided generation |

**Why this fits us better than any competitor:** Apple states indexing fails for large,
server-backed or fast-changing datasets. Scanned documents are **local, finite and static** — the
ideal case. And our output is *structured* (cells, amounts, dates, vendors), which indexes far
better than a rival's flat OCR text layer.

Our work here is protocol conformance and entity modelling, not machine learning.

> **Requires device verification on an iPad beta before it is promised in metadata or captions.**
> New-Siri availability may be region-gated; treat US-only availability as the planning assumption
> until measured.

### 7.5 Platform

| | Who | Note |
|---|---|---|
| iOS + iPadOS + macOS universal | **O** | our standing pattern; Mac is the emptier market (§6) |
| Mac: drag an existing PDF in | **O** | phone-first rivals handle this badly |

### 7.6 The fallback decision — open

Tabular is **iOS 26+ only**, cutting it off from most of the installed base.

Two options, to be decided deliberately:

1. **iOS 26+ only** — pure Apple stack, smallest binary, fastest to ship, same limit as Tabular
2. **iOS 26+ with a fallback path below it** — reuses the existing `derusty/` SAM2Kit +
   Vision work, addressing a materially larger market than the only competitor

Option 2 is the only remaining use for the SAM2 port, which WWDC26 otherwise made redundant.
It is not free: two code paths, two quality bars, two test matrices.

---

## 7.7 Which APIs are shipped vs still in beta — decides the 1.0 target

Verified 2026-08-06. **The split matters: 1.0 needs no beta OS and no beta Xcode.**

| API | Announced | Availability | In 1.0? |
|---|---|---|---|
| `RecognizeDocumentsRequest` | WWDC25 | **iOS/iPadOS/macOS/visionOS/tvOS 26 — shipped** | ✅ yes, it *is* 1.0 |
| Foundation Models (text) | WWDC25 | **26 — shipped** | ✅ optional |
| App Intents / Shortcuts / Spotlight | long shipped | shipped | ✅ yes |
| `GenerateIterativeSegmentationRequest` | WWDC26 | **next OS — beta** | ❌ 1.1 |
| Foundation Models **image input** | WWDC26 | **next OS — beta** | ❌ 1.1 |
| App Schemas / View Annotations / new Siri | WWDC26 | **next OS — beta** | ❌ 1.1 |

**Consequence:** build 1.0 against the **released SDK** with a **deployment target of 26**. Every
1.0 function above is available there. No beta macOS, no beta Xcode, no beta iPad required to ship.

The iPad beta is for **evaluating 1.1** — Siri behaviour, Foundation Models image quality, region
gating — not for building 1.0.

Anything from the beta rows must be added behind an availability check so 1.0 users on 26 are
unaffected.

---

## 8. Risks — stated plainly

1. **The technical moat is gone.** Apple gave every competitor the same extraction. Our defensibility
   is buy-once positioning + verification + workflow — all copyable, none patentable. Speed and ASO
   matter more than usual.
2. **4.3 spam exposure.** 63 generic scanner clones shipped since WWDC25. A generic-looking scanner
   invites the duplicate-app rejection. The verification framing is a review argument as well as a
   marketing one.
3. **Apple ships a free scanner** in Notes and Files. Plain capture is closed; the layer above it —
   structure, verification, export — is the target. (`apple-ships-it-aim-higher`)
4. **Impressions remain the binding constraint.** Every conclusion above concerns whether the niche
   is worth entering. Being seen is a separate, unsolved problem — see the ASO surfaces audit
   (in-app events, search-results asset, custom product pages: currently 0/16 apps).
5. **Tabular may iterate.** It is three weeks old and actively developed. Its subscription is the
   opening; that could change at any release.

---

## 9. Suggested scope

**v1 — the smallest version that still wins:**
table → **verified** CSV/XLSX · multi-page stitching · confidence review · batch import ·
buy-once · iOS + iPad + Mac

**v1.1 — Apple Intelligence + Siri (deferred deliberately, not dropped):**
in-app Q&A over a document · Siri semantic search across scans · onscreen awareness

Reasons to defer rather than ship in v1:

- **It depends on unverified behaviour.** Foundation Models quality on real scanned documents,
  and whether the new Siri is region-gated, are both unknown until tested on the iPad beta. A
  headline feature must not be a guess.
- **It cannot be promised in metadata until measured** — captions and subtitle are indexed and
  effectively permanent for a release cycle; claiming an unverified capability is the worst
  possible place to be wrong.
- **v1's claim is verification.** "Extracted, and the totals reconcile" is what justifies $9.99
  against free CamScanner. Adding a second headline dilutes it.
- **Tabular is actively developed.** Shipping the core claim sooner matters more than shipping
  more of it later.

Reasons it is v1.1 and not v2: the engineering is protocol conformance and entity modelling, not
machine learning, so it is genuinely cheap once the entity model exists. It should land in the
first update, not the second.

**Ships in v1 anyway** — the non-Siri half of App Intents: **Shortcuts actions** and Spotlight
indexing. Those need no Apple Intelligence, no beta, and no region gating, and they lay the entity
model that v1.1 builds on. Doing the modelling once, in v1, is what makes v1.1 cheap.

**v2 — near-free once the `detectedData` plumbing exists, and separate keyword territory:**
receipts (with arithmetic verification) · business cards → vCard/CSV

**Price:** $9.99, matching the proven paid incumbent. No subscription, ever — the entire position
depends on it.

---

## 10. Request to Claude design — 1.0

> Hand this section to the design agent once §11 is closed. Same contract as
> `DESIGN_BRIEF_storypole.md`: the measurement is done, and it is not yours to re-open.

**The one-sentence product:** a document scanner that **proves it read the table correctly** —
extracted numbers reconcile against the document's own totals, and anything that doesn't is
flagged before export.

**What you are designing for.** The buyer is at work. They photograph a table, an invoice or a
statement, and need it in a spreadsheet in the next few minutes without hand-checking every cell.
They have used a free scanner and been burned by a silently wrong number, or by a subscription
that appeared after they had already paid.

**The screens 1.0 needs:**

1. **Capture** — camera with auto-crop, quality/smudge warning before the shot is kept, and batch
   capture. Multi-photo import from Photos is not an edge case; it is a headline complaint (§5).
2. **Review** — the extracted grid over the source image. Low-confidence cells visibly marked.
   Tapping a cell shows the pixels it came from. This screen is the product.
3. **Reconciliation** — the verification result. Totals reconcile, or these three cells are why
   they don't. Must be legible at a glance and must never claim verification it did not perform.
4. **Correct** — fix a cell, drag row/column guides to fix the grid. **Manual correction only in
   1.0**; tap/box/lasso re-segmentation needs an unreleased OS (see §7.7) and arrives later behind
   an availability check.
5. **Multi-page** — pages of one table joined, repeated headers dropped, columns aligned, with the
   join visible and correctable.
6. **Export** — CSV/XLSX, with verified/unverified state carried into the moment of export.
7. **Library** — local, offline, searchable, with export-everything. No account anywhere in the app.

**Non-negotiable constraints:**

- **No subscription. No IAP. Paid-upfront $9.99.** The entire market position rests on this (§4).
  Do not design a paywall, a trial, a credit balance, or an upgrade prompt.
- **No account, no cloud, no network.** If a screen implies an account, it is wrong.
- **Never show a verified state that wasn't computed.** The claim is the product; a false green
  check destroys it. Unverifiable documents (no totals row) get an honest "nothing to check
  against," not a pass.
- **Universal: iPhone, iPad, macOS.** Mac must accept a dragged-in PDF as a first-class entry
  point, not a port afterthought.
- Accessibility floor per the house standard — Dynamic Type, VoiceOver on the grid, and the
  confidence marking must not rely on colour alone.

**What you may decide:** visual language and design system, capture flow ergonomics, how
confidence is represented, grid interaction, onboarding (if any), naming-template UX.

**What you may not decide:** the price, the monetization model, the verification claim's wording,
or whether Apple Intelligence appears in 1.0 — it does not (§9).

**Build on the latest SDK.** Extraction is `RecognizeDocumentsRequest`; correction is
`GenerateIterativeSegmentationRequest`; models arrive via `downloadAssets()`. Ship no weights.
Model entities for App Intents in 1.0 even though Siri lands in 1.1 — that modelling is what makes
1.1 cheap (§9).

**Deliver:** screen inventory with states (empty, mid-scan, low-confidence, reconciliation failed,
export), the design system, and the oracle-facing copy for the reconciliation screen. Flag
anything in this brief that the measurement doesn't actually support rather than designing around
it silently.

---

## 11. Open questions before commitment

- [ ] Verify Foundation Models + App Schemas on an **iPad beta** — availability, quality, region gating
- [ ] Decide §7.4 fallback: iOS 26-only vs dual-path
- [ ] Name and identifier — must not read as a generic scanner (4.3)
- [ ] Confirm `pdf to excel` is winnable against Adobe's free giant, or drop it as a target term
- [ ] Re-check Tabular's monetization at build time; the opening is its subscription
