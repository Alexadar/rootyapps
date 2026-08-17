import Foundation
import CoreGraphics
import Vision
import DocumentModelKit

/// Primary OCR path: RecognizeDocumentsRequest (Vision, iOS/macOS 26 — API verified
/// against the 26.5 swiftinterface). Structure comes from Vision's own document model:
///   DocumentObservation.document (Container) → .tables[].rows: [[Cell]] (cells carry
///   rowRange/columnRange spans), .paragraphs/.lists for non-table text, .title.
/// Confidence: Cell.content.text.lines are RecognizedTextObservations with a real OCR
/// confidence — the only confidence that exists; it becomes review flags, never data.
enum VisionAdapter {

    static func extract(image: CGImage, pageIndex: Int) async throws -> PageExtraction {
        let request = RecognizeDocumentsRequest()
        let observations = try await ImageRequestHandler(image).perform(request)
        guard let container = observations.first?.document else {
            return PageExtraction()
        }
        var out = PageExtraction()
        out.titleGuess = container.title?.transcript
            .trimmingCharacters(in: .whitespacesAndNewlines)

        for table in container.tables {
            let tableIndex = out.tables.count
            // Grid dimensions from the span ranges (merged cells cover ranges).
            let allCells = table.rows.flatMap { $0 }
            let rowCount = (allCells.map(\.rowRange.upperBound).max() ?? -1) + 1
            let colCount = (allCells.map(\.columnRange.upperBound).max() ?? -1) + 1
            guard rowCount > 0, colCount > 0 else { continue }

            var grid = [[Cell]](repeating: [Cell](repeating: Cell(""), count: colCount),
                                count: rowCount)
            var seen = Set<String>()
            var low: [(Int, Int, String)] = []
            for cell in allCells {
                // A spanning cell appears once per covered row in `rows`; anchor it at
                // its range origin and leave covered positions empty (prov on anchor).
                let key = "\(cell.rowRange)-\(cell.columnRange)"
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                let r = cell.rowRange.lowerBound
                let c = cell.columnRange.lowerBound
                guard r < rowCount, c < colCount else { continue }
                let text = cell.content.text.transcript
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let prov = CoordinateMapper.bbox(cell.content.boundingRegion,
                                                 pageIndex: pageIndex)
                grid[r][c] = Cell(text, prov: [prov])
                if !text.isEmpty,
                   minConfidence(of: cell.content.text) < ExtractionTuning.lowOCRConfidence {
                    low.append((r, c, text))
                }
            }
            let assembled = Table(normalizing: grid).trimmedEmptyEdges()
            guard assembled.rowCount > 0 else { continue }
            out.tables.append(assembled)
            for (r, c, text) in low where r < assembled.rowCount && c < assembled.columnCount {
                out.lowConfidence.append(.cell(tableIndex: tableIndex, row: r,
                                               column: c, text: text))
            }
        }

        // Non-table text, in the order Vision reports it (reading order — never sorted).
        for paragraph in container.paragraphs {
            appendSpan(from: paragraph, pageIndex: pageIndex, into: &out)
        }
        for list in container.lists {
            for item in list.items {
                let text = (item.markerString + " " + item.itemString)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                out.loose.append(TextSpan(text, prov: [
                    CoordinateMapper.bbox(item.content.boundingRegion, pageIndex: pageIndex),
                ]))
            }
        }
        return out
    }

    private static func appendSpan(from text: DocumentObservation.Container.Text,
                                   pageIndex: Int, into out: inout PageExtraction) {
        let transcript = text.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return }
        let span = TextSpan(transcript, prov: [
            CoordinateMapper.bbox(text.boundingRegion, pageIndex: pageIndex),
        ])
        if minConfidence(of: text) < ExtractionTuning.lowOCRConfidence {
            out.lowConfidence.append(.span(id: span.id, text: transcript))
        }
        out.loose.append(span)
    }

    private static func minConfidence(of text: DocumentObservation.Container.Text) -> Float {
        text.lines.map(\.confidence).min() ?? 1
    }
}
