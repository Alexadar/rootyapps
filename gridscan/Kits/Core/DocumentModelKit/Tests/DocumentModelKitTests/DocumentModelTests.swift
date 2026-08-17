import Testing
import Foundation
@testable import DocumentModelKit

/// Oracle = the tier-one model contract in gridscan/PROMPT.md: rectangular tables of TEXT
/// cells, no commerce semantics, provenance as an array with explicit coord_origin,
/// citation-addressable below the page, loose text in reading order, frozen Codable schema.
@Suite struct DocumentModelTests {

    @Test func normalizationPadsRaggedRows() {
        let t = Table(normalizing: [["a", "b", "c"], ["d"], []])
        #expect(t.columnCount == 3)
        #expect(t.textRows == [["a", "b", "c"], ["d", "", ""], ["", "", ""]])
    }

    @Test func emptyTableIsZeroByZero() {
        let t = Table(normalizing: [] as [[String]])
        #expect(t.rowCount == 0)
        #expect(t.columnCount == 0)
    }

    @Test func trimRemovesOuterEmptyEdgesOnly() {
        let t = Table(normalizing: [
            ["", "", "", ""],
            ["", "a", "", ""],
            ["", "", "", ""],    // interior empty row between a and b must survive
            ["", "b", "", "x"],
            ["", "", "", ""],
        ]).trimmedEmptyEdges()
        #expect(t.textRows == [["a", "", ""], ["", "", ""], ["b", "", "x"]])
    }

    @Test func trimOfAllEmptyIsEmpty() {
        let t = Table(normalizing: [["", ""], ["", ""]]).trimmedEmptyEdges()
        #expect(t.rowCount == 0)
    }

    @Test func codableRoundTrip() throws {
        let doc = ScanDocument(
            title: "Site log", date: Date(timeIntervalSinceReferenceDate: 789_000_000),
            kind: .table,
            pages: [Page(index: 0,
                         tables: [Table(normalizing: [["h1", "h2"], ["v1", "v2"]])],
                         looseText: [TextSpan("footer note")])])
        let data = try JSONEncoder().encode(doc)
        let back = try JSONDecoder().decode(ScanDocument.self, from: data)
        #expect(back == doc)
    }

    @Test func rawValuesAreFrozen() {
        // Storage format — changing these silently corrupts persisted archives.
        #expect(DocumentKind.table.rawValue == "table")
        #expect(DocumentKind.form.rawValue == "form")
        #expect(DocumentKind.report.rawValue == "report")
        #expect(DocumentKind.allCases.count == 3)
        #expect(CoordOrigin.topLeft.rawValue == "top-left")
        #expect(CoordOrigin.bottomLeft.rawValue == "bottom-left")
    }

    @Test func textSurfacesAreInReadingOrderAndNonEmpty() {
        let doc = ScanDocument(title: "t", kind: .form, pages: [
            Page(index: 0, tables: [Table(normalizing: [["a", ""], ["b", "c"]])],
                 looseText: [TextSpan(""), TextSpan("loose")]),
            Page(index: 1, tables: [], looseText: [TextSpan("p2")]),
        ])
        #expect(doc.allText == ["a", "b", "c", "loose", "p2"])
        #expect(doc.allTables.count == 1)
    }

    // MARK: citation addressability (tier-one obligation — v2 retrieval cites against this)

    @Test func cellAddressResolvesToProvenanceAfterCodableRoundTrip() throws {
        let prov = Provenance(pageIndex: 0,
                              bbox: BBox(x: 0.5, y: 0.25, width: 0.125, height: 0.0625,
                                         origin: .topLeft))
        let table = Table(normalizing: [[Cell("h")], [Cell("v", prov: [prov])]])
        let doc = ScanDocument(title: "t", kind: .table,
                               pages: [Page(index: 0, tables: [table])])
        let back = try JSONDecoder().decode(ScanDocument.self,
                                            from: try JSONEncoder().encode(doc))
        let addr = CellAddress(documentID: doc.id, pageIndex: 0, tableID: table.id,
                               row: 1, column: 0)
        let cell = back.cell(at: addr)
        #expect(cell?.text == "v")
        #expect(cell?.prov == [prov])                       // bbox + coord_origin survive
        // Misses resolve to nil, never to a wrong cell.
        #expect(back.cell(at: CellAddress(documentID: UUID(), pageIndex: 0,
                                          tableID: table.id, row: 1, column: 0)) == nil)
        #expect(back.cell(at: CellAddress(documentID: doc.id, pageIndex: 0,
                                          tableID: table.id, row: 9, column: 0)) == nil)
    }

    @Test func spanAddressResolvesAndOrderSurvivesRoundTrip() throws {
        let spans = (0..<5).map { TextSpan("s\($0)") }
        let doc = ScanDocument(title: "t", kind: .report,
                               pages: [Page(index: 0, looseText: spans)])
        let back = try JSONDecoder().decode(ScanDocument.self,
                                            from: try JSONEncoder().encode(doc))
        // Reading order is the array order and must survive persistence — chunking
        // contiguous text later depends on it and it cannot be reconstructed.
        #expect(back.pages[0].looseText.map(\.text) == ["s0", "s1", "s2", "s3", "s4"])
        let addr = SpanAddress(documentID: doc.id, pageIndex: 0, spanID: spans[3].id)
        #expect(back.span(at: addr)?.text == "s3")
        #expect(back.span(at: SpanAddress(documentID: doc.id, pageIndex: 0,
                                          spanID: UUID())) == nil)
    }

    // MARK: frozen wire format

    @Test func encodedFieldNamesAreAPublicContract() throws {
        // Golden encoding with pinned IDs. If this test breaks, the schema changed —
        // that is a MIGRATION, not a rename. Field names may be serialized outward.
        let doc = ScanDocument(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            title: "T", date: Date(timeIntervalSinceReferenceDate: 0), kind: .table,
            pages: [Page(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                index: 0,
                tables: [Table(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                    normalizing: [[Cell("v", prov: [Provenance(
                        pageIndex: 0,
                        bbox: BBox(x: 0.5, y: 0.25, width: 0.125, height: 0.0625,
                                   origin: .topLeft))])]])],
                looseText: [TextSpan(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
                    "note")])])
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let json = String(decoding: try enc.encode(doc), as: UTF8.self)
        #expect(json == #"{"date":0,"id":"00000000-0000-0000-0000-000000000001","kind":"table","pages":[{"id":"00000000-0000-0000-0000-000000000002","index":0,"looseText":[{"id":"00000000-0000-0000-0000-000000000004","prov":[],"text":"note"}],"tables":[{"id":"00000000-0000-0000-0000-000000000003","rows":[[{"prov":[{"bbox":{"height":0.0625,"origin":"top-left","width":0.125,"x":0.5,"y":0.25},"pageIndex":0}],"text":"v"}]]}]}],"title":"T"}"#)
    }
}
