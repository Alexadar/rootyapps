# GridScan — product spec (restored after deliberate clean restart, 2026-08-17)

The previous `gridscan/` tree was wiped intentionally by the owner and rebuilt from this spec.
Sources of record: `docs/CANDIDATE_scanner_2026-08-06.md`, `docs/CANDIDATE_doc_extractor_2026-08-16.md`,
owner ruling of 2026-08-17 (memory `gridscan-tier-one-abstract-tabular`), `docs/new_app_blueprint.md`.

## One line

On-device document → structured tabular data → human verification → clean CSV/XLSX export.
**$9.99 paid upfront**, no ads, no subscription, no account, no server. iPhone + iPad, iOS/iPadOS 26+.
macOS target planned (the measured market gap — "macOS is markedly emptier", 2026-08-06).

## Hierarchy (2026-08-17, rootyapps-master session, corroborates the owner ruling)

In order: **a place documents live → something you can question → something that validates what
it read.** The archive is the centre of gravity; capture is one of several ways in. The prior
build's work orders ("verification is still the product", `ReconcileKit`, `MatchKit`) are
SUPERSEDED — there is no arithmetic checking in this product. Quality = the structure is complete
and well-formed (format rules, required-field-missing, low OCR confidence), never "the numbers
agree". All functionality on all three platforms (iPhone/iPad/Mac, one universal app); Kits stay
platform-agnostic (no UIKit/AppKit/SwiftUI).

## Tier one = a DOCUMENT DATABASE over ABSTRACT TABULAR DATA (owner ruling, binding)

The surfaced model is:

    document → pages → tables (rows × columns of TEXT cells) → loose text
    plus: title, date, structural kind (table / form / report)

**FORBIDDEN in tier one, UX and vocabulary alike:** totals, vendors, amounts, currencies,
quantities, prices, computed sums, verification verdicts, "didn't add up", label gates,
answerable counts. These are receipt-frame *interpretations* of cells, not data. They belong to a
deferred receipt/invoice sub-option ("Check the numbers") which is not built in tier one.
When dissecting a feature, remove its data vocabulary, not only its computations.
Ask/search surfaces are **retrieval + citation only** in tier one.

## Honesty rules (from the 2026-08-16 review — binding)

- **Confidence:** Vision OCR exposes real per-observation confidence; Foundation Models structured
  output does not expose per-field extraction confidence. Flag only what is computable: OCR-layer
  confidence, missing cells, failed format rules. Never render an invented confidence badge.
- **No unconditional "end-to-end encrypted" claim** in store copy. CloudKit private DB is "your own
  iCloud, no developer server" — that phrasing is true and sufficient.
- **Hardware gate up front:** any Apple Intelligence-dependent feature must state its device
  requirement in store copy and the first screenshot, not a footnote (paid-upfront + dead feature =
  refund + 1★).

## ASO (measured, do not relearn)

- Rank on **`document scanner` / `pdf ocr` / `receipt scanner`** — where the paid-once precedent
  lives (TurboScan Pro $9.99 · 295k ratings). Differentiate on tables/export — never the reverse.
- Parser/extraction/webhook/automation vocabulary measures **zero** hints (10 of 11 terms). Never
  lead with it. Destination brands (Airtable/Notion/n8n/webhook) are the CRM trap.
- Stay out of `chat with pdf` (saturated ChatPDF clones, wrong buyer).
- One app record. The Mac version is a GridScan target, never a second app (4.3 catalog risk).

## Search scoping (two layers, never collide)

| Layer | Job | When |
|---|---|---|
| `CSUserQuery` / Spotlight | find the **document** — Apple-managed index | 1.0 |
| Local embeddings (`NLContextualEmbedding` + SQLite cosine) | retrieve the **passage** to cite | v2 |

v2 RAG storage design (decided 2026-08-16): text chunks + extraction records sync via CloudKit
private database (SwiftData + CloudKit); **vectors never sync** — device-local derived cache,
re-embedded per device (embedding models drift across OS releases; synced vectors degrade silently).
FM answers must cite and display the retrieved snippet; retrieval-only is the default, generation
is opt-in.

## Architecture

- **Extraction seam:** Vision `RecognizeDocumentsRequest` (iOS 26) provides document structure
  incl. tables; plain `VNRecognizeTextRequest` OCR is the fallback path. The seam is app-layer —
  Kits never import Vision.
- **Kits (Foundation-only SPM, oracle-tested — the moat):**
  - `Kits/Core/DocumentModelKit` — the tier-one data model (document/page/table/cells/loose text),
    Codable, stable IDs, grid normalization. **Tier-one obligation (agreed 2026-08-17):** every
    cell and loose-text span is citation-addressable below the page (`CellAddress`/`SpanAddress`
    resolve to text + `prov: [Provenance]` with bbox + coord_origin after a Codable round-trip),
    and loose text is an ORDERED array (reading order is unreconstructable later). The encoded
    field names are a frozen public contract (golden-JSON test); changing them is a migration.
  - `Kits/Structure/TableStructureKit` — geometry: positioned text runs → blocks → rows × column
    bands → grid. Adapter for the OCR-fallback path; golden-fixture tested.
  - `Kits/Export/CSVExportKit` — RFC 4180 writer (+ optional UTF-8 BOM for Excel).
  - `Kits/Export/XLSXExportKit` — minimal ECMA-376 .xlsx (own ZIP container, stored entries,
    inline strings); sheet-name rules per Excel limits.
- Deferred (not in tree): receipt sub-option kits ("Check the numbers"); RetrievalKit (v2 —
  depends on the app-layer persistence schema; passage retrieval is a product-page
  differentiator, never discovery); outbound JSON payload contract for destinations/webhooks —
  when it lands it gets the same golden-file discipline as XLSX, plus: money never as a JSON
  number (float rounding corrupts silently — though tier one has no money fields at all),
  ISO 8601 dates, `schema_version` with additive-only changes within a major, never repurpose
  a field name.

## Expensive-to-retrofit specifics (from the prior build, keep)

- **Branch per PAGE, not per file:** born-digital PDF pages use the text layer and must NOT be
  OCR'd; scanned pages render at ~300 DPI (not the 72 default). A usable text layer is not
  `page.string != nil` — bad prior OCR leaves a garbage layer.
- **Provenance is an array**, and every bbox carries an explicit `coord_origin` — PDF is
  bottom-left origin, rendered images top-left; the mismatch mirrors boxes vertically without
  erroring.
- **Per-field extraction confidence must be structurally impossible to populate** from the
  extraction path (only OCR-layer confidence is real).
- **App Intents entities expose a structured ROW, not just a document** — retrofitting means
  reindexing.

## Pipeline status

- P0 decided (this file). P1 Kits green. P2 design approved by iteration (CD mockups,
  corrected round 2, in design/swift-mockups/). **P4 built 2026-08-17**: production app
  (import + camera scan + extraction + SwiftData store + CSV/XLSX export + Spotlight),
  iOS + macOS builds green, 15 unit tests green, UI tests WRITTEN but not yet run
  (explicit order — run them next session; JoinSplit UITest still needs a multi-page
  PDF fixture). Icon: gridscan.icon (3×3 glyph, symmetry pixel-asserted in
  tools/make_icon.py).
- Bundle id `oleksandr.aisixteen.gridscan` (already registered; the old 1.0.0 (1) archive exists at
  /private/tmp/gs-archives but is dead — record never shipped, version debuts at 1.0.0).
- Set `PRODUCT_NAME: GridScan` explicitly (App Review 5.2.5 trap).
