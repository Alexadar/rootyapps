import Foundation

// ⚠️ EXAMPLES ONLY — none of this content ships in the product.
// Column names, source names, and every value here exist purely to preview
// the UI. The real app has NO predefined columns: they come from each
// scanned document at runtime. Samples are deliberately domain-diverse and
// non-commerce — no vendors, amounts, currencies, prices, or totals.
enum SampleData {
    static let documents: [Document] = [
        .init(title: "Soil sample log — Plot 7 spring survey", meta: "14 Mar 2026 · 3 pages · 41 rows",
              kind: .table, unresolvedReviewCount: 4),
        .init(title: "Race results — 200 m freestyle heats", meta: "12 Mar 2026 · 2 pages · 24 rows",
              kind: .table, unresolvedReviewCount: 0),
        .init(title: "Vaccination roster — Ward B", meta: "11 Mar 2026 · 5 pages · 62 rows",
              kind: .table, unresolvedReviewCount: 0, isDownloaded: false),
        .init(title: "Daily observations — Station Kestrel", meta: "10 Mar 2026 · 6 pages · 118 rows",
              kind: .table, unresolvedReviewCount: 0),
        .init(title: "Maintenance checklist — press no. 3", meta: "9 Mar 2026 · 1 page · 12 fields",
              kind: .form, unresolvedReviewCount: 1),
        .init(title: "Accession register — March additions", meta: "9 Mar 2026 · 4 pages",
              kind: .report, unresolvedReviewCount: 0, isDownloaded: false),
    ]
    // Example grid (soil sample log): columns as read — "Sample ID / Depth / pH".
    static let destinations: [Destination] = []
    static let events: [AuditEvent] = []
}
