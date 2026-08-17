#if DEBUG
import Foundation
import DocumentModelKit

/// UITest/dev seed data — real ScanDocument values through the REAL store (an ephemeral
/// container), never a mock layer. Domain-diverse and non-commerce by ruling: no vendors,
/// amounts, currencies, prices, totals. DEBUG-only; Release has no fixtures.
enum FixtureCatalog {

    struct Seed {
        var document: ScanDocument
        var flags: [ReviewFlag]
    }

    static func standard() -> [Seed] {
        var seeds: [Seed] = []

        // 1 — soil sample log (flagged: one low-OCR-confidence cell)
        let soilID = UUID()
        let soilTable = Table(normalizing: [
            ["Sample ID", "Depth cm", "pH", "Moisture %"],
            ["P7-001", "10", "6.8", "23"],
            ["P7-002", "30", "6.5", "27"],
            ["P7-003", "50", "6.I", "31"],          // the mis-read the flag points at
            ["P7-004", "70", "7.0", "29"],
        ])
        let soil = ScanDocument(
            id: soilID, title: "Soil sample log \u{2014} Plot 7 spring survey",
            date: date(2026, 3, 14), kind: .table,
            pages: [Page(index: 0, tables: [soilTable],
                         looseText: [TextSpan("Sampled after 48h dry weather")])])
        seeds.append(Seed(document: soil, flags: [
            ReviewFlag(id: UUID(), documentID: soilID,
                       address: .cell(CellAddress(documentID: soilID, pageIndex: 0,
                                                  tableID: soilTable.id, row: 3, column: 2)),
                       reason: .lowOCRConfidence, status: .open,
                       originalText: "Read as \u{201C}6.I\u{201D}", correctedText: nil),
        ]))

        // 2 — race results
        let race = ScanDocument(
            id: UUID(), title: "Race results \u{2014} 200 m freestyle heats",
            date: date(2026, 3, 12), kind: .table,
            pages: [Page(index: 0, tables: [Table(normalizing: [
                ["Lane", "Swimmer", "Heat", "Time"],
                ["1", "J. Okafor", "1", "2:04.31"],
                ["2", "M. Silva", "1", "2:06.90"],
                ["3", "T. Lind", "2", "2:03.77"],
            ])])])
        seeds.append(Seed(document: race, flags: []))

        // 3 — vaccination roster
        let roster = ScanDocument(
            id: UUID(), title: "Vaccination roster \u{2014} Ward B",
            date: date(2026, 3, 11), kind: .table,
            pages: [Page(index: 0, tables: [Table(normalizing: [
                ["Patient code", "Dose", "Date given", "Nurse"],
                ["WB-114", "2nd", "11 Mar 2026", "K. Ade"],
                ["WB-115", "1st", "11 Mar 2026", "K. Ade"],
            ])])])
        seeds.append(Seed(document: roster, flags: []))

        // 4 — weather observations (two pages)
        let weather = ScanDocument(
            id: UUID(), title: "Daily observations \u{2014} Station Kestrel",
            date: date(2026, 3, 10), kind: .table,
            pages: [
                Page(index: 0, tables: [Table(normalizing: [
                    ["Hour", "Temp \u{00B0}C", "Wind kt", "Cloud"],
                    ["06:00", "4.2", "11", "overcast"],
                    ["12:00", "9.8", "14", "broken"],
                ])]),
                Page(index: 1, tables: [Table(normalizing: [
                    ["Hour", "Temp \u{00B0}C", "Wind kt", "Cloud"],
                    ["18:00", "7.1", "9", "scattered"],
                ])], looseText: [TextSpan("Barograph trace attached")]),
            ])
        seeds.append(Seed(document: weather, flags: []))

        // 5 — maintenance checklist (form)
        let checklist = ScanDocument(
            id: UUID(), title: "Maintenance checklist \u{2014} press no. 3",
            date: date(2026, 3, 9), kind: .form,
            pages: [Page(index: 0, tables: [], looseText: [
                TextSpan("Guards secure: yes"), TextSpan("Oil level: ok"),
                TextSpan("Belt wear: replace at next stop"), TextSpan("E-stop test: pass"),
                TextSpan("Hydraulic hoses: ok"), TextSpan("Anchor bolts torque: checked"),
                TextSpan("Light curtain: aligned"), TextSpan("Signed: R. Vane"),
            ])])
        seeds.append(Seed(document: checklist, flags: []))

        // 6 — accession register (report)
        let register = ScanDocument(
            id: UUID(), title: "Accession register \u{2014} March additions",
            date: date(2026, 3, 9), kind: .report,
            pages: [Page(index: 0, tables: [], looseText: [
                TextSpan("Twelve volumes accessioned this month, of which three are "
                         + "donations from the estate sale and nine were purchased "
                         + "through the regional consortium agreement."),
                TextSpan("Condition notes filed separately under shelf audit 2026-03."),
            ])])
        seeds.append(Seed(document: register, flags: []))

        return seeds
    }

    static func seed(into store: any DocumentStore) async {
        for seed in standard() {
            _ = try? await store.create(seed.document, flags: seed.flags, source: .fixture,
                                        detailLines: ["fixture seed"])
        }
    }

    private static func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = 12
        return Calendar(identifier: .gregorian).date(from: c) ?? .now
    }
}
#endif
