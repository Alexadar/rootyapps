import Foundation
import DocumentModelKit
import CSVExportKit
import XLSXExportKit

/// Tier-one destinations: CSV file and XLSX file. Nothing leaves without an explicit
/// user tap; every export is audited (including rows still marked for review).
enum ExportKind: String, CaseIterable, Identifiable, Sendable {
    case csvFile
    case xlsxFile

    var id: String { rawValue }
    var displayName: String { self == .csvFile ? "CSV file" : "Excel workbook (XLSX)" }
    var formatDescription: String {
        self == .csvFile ? "RFC 4180, UTF-8 with BOM" : "ECMA-376 spreadsheet, inline strings"
    }
    var fileExtension: String { self == .csvFile ? "csv" : "xlsx" }
}

struct ExportPayload: Sendable {
    var data: Data
    var suggestedName: String
}

final class ExportService: Sendable {

    let store: any DocumentStore

    init(store: any DocumentStore) {
        self.store = store
    }

    /// Builds the file for a whole document (one sheet per table for XLSX; tables
    /// stacked with a blank line for CSV). The audit event is recorded by `recordExport`
    /// AFTER the save completes — the trail reflects what actually left.
    func payload(for stored: StoredDocument, kind: ExportKind) -> ExportPayload {
        let tables = stored.document.allTables
        let name = sanitizedFileName(stored.summary.title)
        switch kind {
        case .csvFile:
            var rows: [[String]] = []
            for (i, table) in tables.enumerated() {
                if i > 0 { rows.append([]) }
                rows.append(contentsOf: table.textRows)
            }
            return ExportPayload(data: CSV.data(rows, options: .init(includeBOM: true)),
                                 suggestedName: "\(name).csv")
        case .xlsxFile:
            let sheets = tables.enumerated().map { i, table in
                XLSX.Sheet(name: tables.count == 1 ? "Table" : "Table \(i + 1)",
                           rows: table.textRows)
            }
            return ExportPayload(data: XLSX.data(sheets: sheets),
                                 suggestedName: "\(name).xlsx")
        }
    }

    func recordExport(of stored: StoredDocument, kind: ExportKind, destination: String) async {
        let rows = stored.document.allTables.reduce(0) { $0 + $1.rowCount }
        var lines = [
            "\(stored.summary.title) \u{00B7} \(rows) row(s) \u{00B7} \(stored.document.allTables.count) table(s)",
            "Written as \(kind.displayName) to \(destination)",
        ]
        let unresolved = stored.flags.filter { $0.status == .open }.count
        if unresolved > 0 {
            lines.append("Included \(unresolved) value(s) still marked for review")
        }
        try? await store.appendEvent(AuditEvent(
            id: UUID(), documentID: stored.summary.id, kind: .exportedFile,
            timestamp: .now, title: "Exported \u{201C}\(stored.summary.title)\u{201D}",
            detailLines: lines))
    }

    private func sanitizedFileName(_ raw: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?*\"<>|")
        let cleaned = raw.components(separatedBy: bad).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Export" : cleaned
    }
}
