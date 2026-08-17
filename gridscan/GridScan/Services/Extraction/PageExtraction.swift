import Foundation
import CoreGraphics
import DocumentModelKit
import TableStructureKit

/// One page's extraction output, before document assembly. Low-confidence hits are
/// positional (table index/row/column or span id) — the pipeline turns them into
/// ReviewFlags once the ScanDocument (and its IDs) exists. Cell values NEVER carry a
/// confidence field: OCR-layer confidence is the only confidence and it lives here,
/// transiently, on its way to a flag.
struct PageExtraction: Sendable {
    var tables: [Table] = []
    var loose: [TextSpan] = []
    var lowConfidence: [LowConfidenceHit] = []
    var titleGuess: String?
}

enum LowConfidenceHit: Sendable, Equatable {
    case cell(tableIndex: Int, row: Int, column: Int, text: String)
    case span(id: UUID, text: String)
}

/// Shared assembly for both run-based paths (PDF text layer + Vision fallback):
/// runs → blocks → a block with ≥2 rows and ≥2 column bands becomes a Table (with
/// per-cell provenance from its source runs); anything else becomes loose text spans
/// in reading order.
enum BlockAssembler {

    static func assemble(runs: [TextRun], pageIndex: Int,
                         confidence: [TextRun: Float] = [:],
                         lowConfidenceBelow threshold: Float = ExtractionTuning.lowOCRConfidence)
        -> PageExtraction {
        var out = PageExtraction()
        let rows = TableStructure.rows(of: runs)
        for block in TableStructure.blocks(of: rows) {
            let bands = TableStructure.columnBands(of: block)
            if block.count >= 2, bands.count >= 2 {
                let cellRuns = TableStructure.cellRuns(rows: block, bands: bands)
                let tableIndex = out.tables.count
                let cells: [[Cell]] = cellRuns.enumerated().map { r, row in
                    row.enumerated().map { c, runsInCell in
                        let text = runsInCell.map(\.text).joined(separator: " ")
                        let prov = runsInCell.map {
                            CoordinateMapper.provenance(of: $0, pageIndex: pageIndex)
                        }
                        if runsInCell.contains(where: { (confidence[$0] ?? 1) < threshold }) {
                            out.lowConfidence.append(
                                .cell(tableIndex: tableIndex, row: r, column: c, text: text))
                        }
                        return Cell(text, prov: prov)
                    }
                }
                out.tables.append(Table(normalizing: cells).trimmedEmptyEdges())
            } else {
                for row in block {
                    let text = row.map(\.text).joined(separator: " ")
                    guard !text.isEmpty else { continue }
                    let span = TextSpan(text, prov: row.map {
                        CoordinateMapper.provenance(of: $0, pageIndex: pageIndex)
                    })
                    if row.contains(where: { (confidence[$0] ?? 1) < threshold }) {
                        out.lowConfidence.append(.span(id: span.id, text: text))
                    }
                    out.loose.append(span)
                }
            }
        }
        return out
    }
}

enum ExtractionTuning {
    /// Vision reports discrete-ish OCR confidences; below this a value earns a review
    /// flag. This is OCR-layer confidence — the only confidence that exists.
    static let lowOCRConfidence: Float = 0.5
    /// Scanned pages render at this DPI (the 72-pt default destroys OCR accuracy).
    static let renderDPI: CGFloat = 300
}
