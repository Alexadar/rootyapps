GridScan — SwiftUI mockups
==========================

Companion to the HTML spec board (GridScan Board.dc.html) and README.md spec.
These are DESIGN MOCKUPS in SwiftUI form, not a buildable app: model types
referenced but not defined here (Document, ExtractedTable, SearchResult, …)
are sketched to the minimum the views need.

Files
- DesignTokens.swift   — tokens, Provenance & FlagReason (the honesty constraints)
- AppShell.swift       — one IA on all three platforms; first-run asks for nothing
- LibraryView.swift    — archive home: tiles, bulk select (iPhone too), states
- DataGridView.swift   — the schema-agnostic grid + cell provenance + AX reflow
- ReviewView.swift     — review pass, inline fix, learned-layout banner
- SearchAskView.swift  — search shows what matched; answers opt-in and cited
- JoinSplitView.swift  — multi-page join seams · document split proposals
- DestinationsView.swift — pluggable destination object + the one generic mapper
- ActivityView.swift   — user-facing audit trail
- SampleData.swift     — ⚠️ examples only; six non-commerce worlds (soil log,
                         race results, vaccination roster, weather observations,
                         maintenance checklist, accession register)

Tiers
- TIER ONE: capture, structuring, archive, review, SEARCH ONLY (retrieval +
  citation), CSV + XLSX destinations, activity. Structural kind (table / form /
  report) is a first-class tier-one field: on every tile and a Library filter.
  Kinds describe layout shape, never content meaning.
- V2: the generated-answer layer in Search & Ask (AnswerCard) — opt-in, cited.
- LATER: the .webhook destination kind (blocked on a deferred payload
  contract). The pluggable Destination object and generic mapper are unchanged.

Rules carried from the brief
- Liquid Glass chrome only: .glassEffect(), GlassEffectContainer,
  .buttonStyle(.glass). NEVER .ultraThinMaterial/.regularMaterial/.thinMaterial.
- Documents and grids are opaque paper/data, never glass.
- ⚠️ Sample columns (e.g. "Sample ID", "Depth", "pH") are EXAMPLE content only and
  are NOT part of the final product unless explicitly asked. Columns always
  come from the scanned document at runtime. Samples are non-commerce by rule:
  no vendors, amounts, currencies, prices, totals, or verdicts anywhere.
- No per-field extraction confidence badge exists anywhere. Legitimate flags:
  missing required · failed format rule · low OCR confidence.
- Every generated answer sentence cites; uncited text is not rendered.
- Nothing leaves the device except a user-tapped send to a destination.
