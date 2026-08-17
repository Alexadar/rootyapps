import Foundation
import SwiftData
import DocumentModelKit

/// The production store. UITest fixture runs use THIS same class over an ephemeral
/// in-memory ModelConfiguration — production code path, deterministic data.
@ModelActor
actor SwiftDataDocumentStore: DocumentStore {

    private var continuations: [UUID: AsyncStream<StoreChange>.Continuation] = [:]

    private func notify() {
        for c in continuations.values { c.yield(.documentsChanged) }
    }

    func changes() async -> AsyncStream<StoreChange> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.onTermination = { _ in
                Task { await self.removeContinuation(id) }
            }
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }

    // MARK: reads

    func summaries() async throws -> [DocumentSummary] {
        let records = try modelContext.fetch(
            FetchDescriptor<DocumentRecord>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
        return records.map(summary(of:))
    }

    func storedDocument(id: UUID) async throws -> StoredDocument? {
        guard let record = try fetchRecord(id) else { return nil }
        let doc = try JSONDecoder().decode(ScanDocument.self, from: record.payload)
        return StoredDocument(
            summary: summary(of: record),
            document: doc,
            flags: (record.flags ?? []).compactMap(flag(of:)),
            events: (record.events ?? []).map(event(of:)).sorted { $0.timestamp > $1.timestamp })
    }

    func allEvents() async throws -> [AuditEvent] {
        let records = try modelContext.fetch(
            FetchDescriptor<AuditEventRecord>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)]))
        return records.map(event(of:))
    }

    func search(_ query: String) async throws -> [SearchHit] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        var hits: [SearchHit] = []
        for record in try modelContext.fetch(FetchDescriptor<DocumentRecord>()) {
            guard let doc = try? JSONDecoder().decode(ScanDocument.self, from: record.payload)
            else { continue }
            let flagged = record.unresolvedReviewCount > 0
            if record.title.localizedCaseInsensitiveContains(needle) {
                hits.append(SearchHit(documentID: record.uuid, documentTitle: record.title,
                                      matchedText: record.title, location: "title",
                                      hasUnresolvedFlags: flagged))
            }
            for page in doc.pages {
                for (t, table) in page.tables.enumerated() {
                    for row in table.rows {
                        for cell in row where cell.text.localizedCaseInsensitiveContains(needle) {
                            hits.append(SearchHit(
                                documentID: record.uuid, documentTitle: record.title,
                                matchedText: cell.text,
                                location: "page \(page.index + 1), table \(t + 1)",
                                hasUnresolvedFlags: flagged))
                        }
                    }
                }
                for span in page.looseText
                where span.text.localizedCaseInsensitiveContains(needle) {
                    hits.append(SearchHit(
                        documentID: record.uuid, documentTitle: record.title,
                        matchedText: span.text, location: "page \(page.index + 1) text",
                        hasUnresolvedFlags: flagged))
                }
            }
        }
        return hits
    }

    // MARK: writes

    @discardableResult
    func create(_ doc: ScanDocument, flags: [ReviewFlag], source: ImportSource,
                detailLines: [String]) async throws -> DocumentSummary {
        if try fetchRecord(doc.id) != nil {
            throw StoreError.duplicateDocument(doc.id)     // uniqueness enforced here, not @Attribute
        }
        let record = DocumentRecord()
        record.uuid = doc.id
        try write(doc, into: record)
        record.createdAt = .now
        modelContext.insert(record)
        for f in flags {
            let fr = flagRecord(from: f)
            fr.document = record
            modelContext.insert(fr)
        }
        record.unresolvedReviewCount = flags.filter { $0.status == .open }.count
        appendEventRecord(kind: .imported, document: record,
                          title: "Brought in \u{201C}\(doc.title)\u{201D}",
                          detailLines: detailLines)
        try modelContext.save()
        notify()
        return summary(of: record)
    }

    func apply(_ correction: Correction) async throws {
        guard let record = try fetchRecord(correction.documentID) else { return }
        var doc = try JSONDecoder().decode(ScanDocument.self, from: record.payload)
        guard let old = doc.cell(at: correction.address)?.text else { return }
        doc = rewriting(doc, at: correction.address, text: correction.newText)
        try write(doc, into: record)

        let existing = (record.flags ?? []).first {
            $0.tableUUID == correction.address.tableID
                && $0.row == correction.address.row
                && $0.column == correction.address.column
        }
        let fr = existing ?? {
            let fr = ReviewFlagRecord()
            fr.documentUUID = record.uuid
            fr.pageIndex = correction.address.pageIndex
            fr.tableUUID = correction.address.tableID
            fr.row = correction.address.row
            fr.column = correction.address.column
            fr.document = record
            modelContext.insert(fr)
            return fr
        }()
        if fr.originalText == nil { fr.originalText = old }
        fr.correctedText = correction.newText
        fr.statusRaw = FlagStatus.resolvedByCorrection.rawValue
        fr.resolvedAt = .now
        recomputeUnresolved(record)
        appendEventRecord(kind: .corrected, document: record,
                          title: "Corrected a value in \u{201C}\(record.title)\u{201D}",
                          detailLines: ["Was \u{201C}\(old)\u{201D} \u{2192} now \u{201C}\(correction.newText)\u{201D}"])
        try modelContext.save()
        notify()
    }

    func update(_ doc: ScanDocument, auditTitle: String, detailLines: [String]) async throws {
        guard let record = try fetchRecord(doc.id) else { return }
        try write(doc, into: record)
        appendEventRecord(kind: .structureChanged, document: record,
                          title: auditTitle, detailLines: detailLines)
        try modelContext.save()
        notify()
    }

    func resolveFlag(id: UUID, dismiss: Bool) async throws {
        let all = try modelContext.fetch(FetchDescriptor<ReviewFlagRecord>())
        guard let fr = all.first(where: { $0.uuid == id }) else { return }
        fr.statusRaw = (dismiss ? FlagStatus.dismissed : .resolvedByCorrection).rawValue
        fr.resolvedAt = .now
        if let doc = fr.document { recomputeUnresolved(doc) }
        try modelContext.save()
        notify()
    }

    func appendEvent(_ event: AuditEvent) async throws {
        let record = event.documentID.flatMap { try? fetchRecord($0) }
        appendEventRecord(kind: event.kind, document: record, title: event.title,
                          detailLines: event.detailLines, documentUUID: event.documentID)
        try modelContext.save()
        notify()
    }

    func delete(ids: [UUID]) async throws {
        for id in ids {
            guard let record = try fetchRecord(id) else { continue }
            let title = record.title
            modelContext.delete(record)
            appendEventRecord(kind: .deleted, document: nil,
                              title: "Deleted \u{201C}\(title)\u{201D}", detailLines: [],
                              documentUUID: id)
            PageImageStore.removeDirectory(documentID: id)
        }
        try modelContext.save()
        notify()
    }

    // MARK: helpers

    enum StoreError: Error { case duplicateDocument(UUID) }

    private func fetchRecord(_ id: UUID) throws -> DocumentRecord? {
        var d = FetchDescriptor<DocumentRecord>(predicate: #Predicate { $0.uuid == id })
        d.fetchLimit = 1
        return try modelContext.fetch(d).first
    }

    private func write(_ doc: ScanDocument, into record: DocumentRecord) throws {
        record.payload = try JSONEncoder().encode(doc)
        record.title = doc.title
        record.kindRaw = doc.kind.rawValue
        record.docDate = doc.date
        record.pageCount = doc.pages.count
        record.tableCount = doc.allTables.count
        record.updatedAt = .now
    }

    private func recomputeUnresolved(_ record: DocumentRecord) {
        record.unresolvedReviewCount = (record.flags ?? [])
            .filter { $0.statusRaw == FlagStatus.open.rawValue }.count
    }

    private func appendEventRecord(kind: AuditEventKind, document: DocumentRecord?,
                                   title: String, detailLines: [String],
                                   documentUUID: UUID? = nil) {
        let er = AuditEventRecord()
        er.documentUUID = document?.uuid ?? documentUUID
        er.kindRaw = kind.rawValue
        er.title = title
        er.detailLines = detailLines
        er.document = document
        modelContext.insert(er)
    }

    private func rewriting(_ doc: ScanDocument, at a: CellAddress, text: String) -> ScanDocument {
        var doc = doc
        for (p, page) in doc.pages.enumerated() where page.index == a.pageIndex {
            for (t, table) in page.tables.enumerated() where table.id == a.tableID {
                var rows = table.rows
                guard rows.indices.contains(a.row), rows[a.row].indices.contains(a.column)
                else { continue }
                rows[a.row][a.column].text = text
                doc.pages[p].tables[t] = Table(id: table.id, normalizing: rows)
            }
        }
        return doc
    }

    private func summary(of r: DocumentRecord) -> DocumentSummary {
        DocumentSummary(id: r.uuid, title: r.title,
                        kind: DocumentKind(rawValue: r.kindRaw) ?? .table,
                        date: r.docDate, createdAt: r.createdAt,
                        pageCount: r.pageCount, tableCount: r.tableCount,
                        unresolvedReviewCount: r.unresolvedReviewCount)
    }

    private func flag(of r: ReviewFlagRecord) -> ReviewFlag? {
        let address: FlagAddress
        if let tableID = r.tableUUID, let row = r.row, let column = r.column {
            address = .cell(CellAddress(documentID: r.documentUUID, pageIndex: r.pageIndex,
                                        tableID: tableID, row: row, column: column))
        } else if let spanID = r.spanUUID {
            address = .span(SpanAddress(documentID: r.documentUUID, pageIndex: r.pageIndex,
                                        spanID: spanID))
        } else {
            return nil
        }
        let reason: FlagReason
        switch r.reasonRaw {
        case "failedFormatRule": reason = .failedFormatRule(r.ruleDetail ?? "")
        case "missingRequired": reason = .missingRequired
        default: reason = .lowOCRConfidence
        }
        return ReviewFlag(id: r.uuid, documentID: r.documentUUID, address: address,
                          reason: reason, status: FlagStatus(rawValue: r.statusRaw) ?? .open,
                          originalText: r.originalText, correctedText: r.correctedText)
    }

    private func flagRecord(from f: ReviewFlag) -> ReviewFlagRecord {
        let fr = ReviewFlagRecord()
        fr.uuid = f.id
        fr.documentUUID = f.documentID
        switch f.address {
        case .cell(let a):
            fr.pageIndex = a.pageIndex
            fr.tableUUID = a.tableID
            fr.row = a.row
            fr.column = a.column
        case .span(let a):
            fr.pageIndex = a.pageIndex
            fr.spanUUID = a.spanID
        }
        switch f.reason {
        case .lowOCRConfidence: fr.reasonRaw = "lowOCRConfidence"
        case .failedFormatRule(let rule):
            fr.reasonRaw = "failedFormatRule"
            fr.ruleDetail = rule
        case .missingRequired: fr.reasonRaw = "missingRequired"
        }
        fr.statusRaw = f.status.rawValue
        fr.originalText = f.originalText
        fr.correctedText = f.correctedText
        return fr
    }

    private func event(of r: AuditEventRecord) -> AuditEvent {
        AuditEvent(id: r.uuid, documentID: r.documentUUID,
                   kind: AuditEventKind(rawValue: r.kindRaw) ?? .imported,
                   timestamp: r.timestamp, title: r.title, detailLines: r.detailLines)
    }
}
