import Foundation
import DocumentModelKit

// The protocol seam: UI (and UITests through the real app) bind here and to these
// Sendable value DTOs only. SwiftData never crosses this boundary.

enum ImportSource: String, Sendable {
    case camera, file, fixture
}

struct DocumentSummary: Sendable, Identifiable, Equatable, Hashable {
    let id: UUID
    var title: String
    var kind: DocumentKind
    var date: Date?
    var createdAt: Date
    var pageCount: Int
    var tableCount: Int
    var unresolvedReviewCount: Int
}

/// Where a flag points. Cell and loose-text spans use the Kit's citation addresses.
enum FlagAddress: Sendable, Equatable, Hashable {
    case cell(CellAddress)
    case span(SpanAddress)
}

enum FlagReason: Sendable, Equatable, Hashable {
    case lowOCRConfidence               // the only reason minted by extraction (the honest one)
    case failedFormatRule(String)
    case missingRequired
}

enum FlagStatus: String, Sendable {
    case open, resolvedByCorrection, dismissed
}

struct ReviewFlag: Sendable, Identifiable, Equatable {
    let id: UUID
    var documentID: UUID
    var address: FlagAddress
    var reason: FlagReason
    var status: FlagStatus
    var originalText: String?           // "Read as …" — shown in the fix bar
    var correctedText: String?          // set on fix; drives the corrected(was:) cell state
}

struct Correction: Sendable {
    var documentID: UUID
    var address: CellAddress
    var newText: String
}

enum AuditEventKind: String, Sendable {
    case imported, importFailed, corrected, structureChanged, exportedFile, deleted
}

struct AuditEvent: Sendable, Identifiable, Equatable {
    let id: UUID
    var documentID: UUID?
    var kind: AuditEventKind
    var timestamp: Date
    var title: String
    var detailLines: [String]
}

struct StoredDocument: Sendable {
    var summary: DocumentSummary
    var document: ScanDocument
    var flags: [ReviewFlag]
    var events: [AuditEvent]
}

struct SearchHit: Sendable, Identifiable, Equatable {
    var id: String { "\(documentID)-\(matchedText)-\(location)" }
    var documentID: UUID
    var documentTitle: String
    var matchedText: String             // WHAT matched — a value, never a filename
    var location: String                // human description: "page 2, table 1" / "page 3 text"
    var hasUnresolvedFlags: Bool
}

enum StoreChange: Sendable {
    case documentsChanged
}

protocol DocumentStore: Sendable {
    func summaries() async throws -> [DocumentSummary]
    func storedDocument(id: UUID) async throws -> StoredDocument?
    @discardableResult
    func create(_ doc: ScanDocument, flags: [ReviewFlag], source: ImportSource,
                detailLines: [String]) async throws -> DocumentSummary
    /// Rewrites the payload cell text, upserts the flag at that address as
    /// resolvedByCorrection (originalText = old value), recomputes counts, audits.
    func apply(_ correction: Correction) async throws
    /// Full-document structural update (join/split/rename/kind); audited.
    func update(_ doc: ScanDocument, auditTitle: String, detailLines: [String]) async throws
    func resolveFlag(id: UUID, dismiss: Bool) async throws
    func appendEvent(_ event: AuditEvent) async throws
    func delete(ids: [UUID]) async throws
    func allEvents() async throws -> [AuditEvent]
    func search(_ query: String) async throws -> [SearchHit]
    func changes() async -> AsyncStream<StoreChange>
}
