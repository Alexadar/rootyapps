import XCTest
import SwiftData
import DocumentModelKit
@testable import GridScan

/// The production store against an in-memory container: payload round-trip, citation
/// resolution after reload, correction semantics, audit-outlives-deletion.
final class StoreRoundTripTests: XCTestCase {

    private func makeStore() throws -> SwiftDataDocumentStore {
        let schema = Schema([DocumentRecord.self, ReviewFlagRecord.self,
                             AuditEventRecord.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        return SwiftDataDocumentStore(modelContainer: container)
    }

    func testCreateReloadAndResolveCellAddress() async throws {
        let store = try makeStore()
        let table = Table(normalizing: [["h"], ["v"]])
        let doc = ScanDocument(title: "t", kind: .table,
                               pages: [Page(index: 0, tables: [table])])
        _ = try await store.create(doc, flags: [], source: .fixture, detailLines: [])
        let loaded = try await store.storedDocument(id: doc.id)
        XCTAssertEqual(loaded?.document, doc)
        let addr = CellAddress(documentID: doc.id, pageIndex: 0, tableID: table.id,
                               row: 1, column: 0)
        XCTAssertEqual(loaded?.document.cell(at: addr)?.text, "v")
    }

    func testCorrectionRewritesPayloadAndResolvesFlag() async throws {
        let store = try makeStore()
        let table = Table(normalizing: [["h"], ["6.I"]])
        let doc = ScanDocument(title: "t", kind: .table,
                               pages: [Page(index: 0, tables: [table])])
        let addr = CellAddress(documentID: doc.id, pageIndex: 0, tableID: table.id,
                               row: 1, column: 0)
        let flag = ReviewFlag(id: UUID(), documentID: doc.id, address: .cell(addr),
                              reason: .lowOCRConfidence, status: .open,
                              originalText: "Read as \u{201C}6.I\u{201D}",
                              correctedText: nil)
        _ = try await store.create(doc, flags: [flag], source: .fixture, detailLines: [])

        try await store.apply(Correction(documentID: doc.id, address: addr, newText: "6.1"))
        let loaded = try await store.storedDocument(id: doc.id)
        XCTAssertEqual(loaded?.document.cell(at: addr)?.text, "6.1")
        XCTAssertEqual(loaded?.summary.unresolvedReviewCount, 0)
        let resolved = loaded?.flags.first { $0.id == flag.id }
        XCTAssertEqual(resolved?.status, .resolvedByCorrection)
        XCTAssertEqual(resolved?.correctedText, "6.1")
        // The correction is audited.
        XCTAssertTrue(loaded?.events.contains { $0.kind == .corrected } ?? false)
    }

    func testAuditTrailOutlivesDeletion() async throws {
        let store = try makeStore()
        let doc = ScanDocument(title: "gone", kind: .report,
                               pages: [Page(index: 0)])
        _ = try await store.create(doc, flags: [], source: .fixture, detailLines: [])
        try await store.delete(ids: [doc.id])
        let afterDelete = try await store.storedDocument(id: doc.id)
        XCTAssertNil(afterDelete)
        let events = try await store.allEvents()
        XCTAssertTrue(events.contains { $0.kind == .imported })
        XCTAssertTrue(events.contains { $0.kind == .deleted })
    }

    func testSearchFindsCellValuesNotFilenames() async throws {
        let store = try makeStore()
        let doc = ScanDocument(title: "Race results", kind: .table, pages: [
            Page(index: 0, tables: [Table(normalizing: [["Swimmer"], ["T. Lind"]])]),
        ])
        _ = try await store.create(doc, flags: [], source: .fixture, detailLines: [])
        let hits = try await store.search("Lind")
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.matchedText, "T. Lind")
        XCTAssertEqual(hits.first?.location, "page 1, table 1")
        let noHits = try await store.search("zzz-nothing")
        XCTAssertTrue(noHits.isEmpty)
    }

    func testDuplicateCreateIsRejected() async throws {
        let store = try makeStore()
        let doc = ScanDocument(title: "one", kind: .report, pages: [])
        _ = try await store.create(doc, flags: [], source: .fixture, detailLines: [])
        do {
            _ = try await store.create(doc, flags: [], source: .fixture, detailLines: [])
            XCTFail("duplicate uuid must be rejected")
        } catch {}
    }
}
