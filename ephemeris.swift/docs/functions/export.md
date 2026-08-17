# Export

**Status:** **shipped** — engine and an in-app action. The engine and CLI were long done; there was
**no UI at all** until this pass
**Source:** `EphemerisKit/Sources/EphemerisKit/Export/TimelineExporter.swift`,
`EphemerisKit/Sources/ephemeris-export/main.swift`
**Surfaces:** `Views/ExportSheet.swift` · `Services/ExportPayload.swift` (pure). One ⤴ per
exportable surface — timeline (`export.events`), chart detail (`export.chart`), moon calendar
(`export.moon`) — never a submenu
**Tests:** `ExporterTests.swift` · `ExportPayloadTests.swift` (10)

## Formats: CSV and JSON

⚠️ **Not `.ics`.** The design handoff described the timeline export as ".ics/JSON"; there is no ICS
generator in the Kit, and writing an unproven RFC 5545 serializer to satisfy a document would invert
this project's order — the engine leads, the doc follows. The handoff is corrected instead.

A **chart** exports as JSON only, and specifically as its own `SavedChart` document — the same bytes
iCloud syncs and `ChartStoreTests` round-trips. A CSV of a chart would be a flattened lookalike of a
file that already has a canonical form.

⚠️ **The sheet states the count and range before anything happens**, and both are read from the same
array the file is written from. A summary computed separately from the bytes is the failure nobody
sees: neither the number nor the file looks wrong alone.

Nothing uploads. The file is written to the temporary directory and handed to the share sheet.

## What it does

Gets results out in a form other tools accept — timelines to calendar-compatible output, charts to
a serialisable representation. There is also a command-line target (`ephemeris-export`), which is
the seam that makes the engine usable outside the app and testable outside Xcode.

## Why anyone pays

Practitioners live in other software too. A tool that traps its output is a tool they use less.
Export is rarely the reason someone buys, and often the reason someone stays.

Note the parallel from the document-scanning market measured in this monorepo: **export was the
single most-complained-about missing feature across every incumbent.** Everyone computes
acceptably; nobody gets structured data back out cleanly. That finding transfers.

## The oracle

**Kind: construction.** Export is a contract, and contracts are golden-file territory.

| Identity | Must hold |
|---|---|
| Round-trip | export → re-import → recompute yields identical values |
| Byte determinism | the same input produces byte-identical output, every run — no map ordering, no timestamps in the payload |
| Golden freeze | a committed expected-output file must match exactly; changing it is a deliberate migration, never an accidental rename |
| Escaping | separators, quotes, newlines and non-ASCII in a chart name survive intact |
| Time zone fidelity | exported instants carry their zone explicitly; a naive local time is a defect |
| Schema versioning | the payload declares its version; changes within a major are additive only |

⚠️ **Once shipped, the export format is a public contract.** Someone's calendar, spreadsheet or
script depends on those field names. Renaming a field is a migration decision.

**What a wrong implementation cannot fake:** byte determinism. Dictionary iteration order and
locale-dependent number formatting both produce output that is *correct* and *different every
run* — which silently breaks every downstream diff.

## Suggested design

- **One obvious export action** per surface, not a submenu.
- **Say what will be exported before it happens** — "12 events, 2026-08-17 to 2026-12-31" beats a
  file appearing.
- Calendar output for [[events]]; chart data for [[natal-chart]].
- ⚠️ **Never imply a server.** Export writes a file the user chooses the destination for. Nothing
  uploads.
- Locale: dates in the exported payload are ISO 8601, always — human-readable formatting belongs
  in the UI, never in the file.

## Failure modes

- Locale-dependent number or date formatting in the payload
- Non-deterministic ordering from an unordered collection
- Silently dropping a field when a value is absent, rather than encoding absence
- Changing a field name without a version bump

## Related

[[events]] · [[natal-chart]] · [[cross-aspects]]
