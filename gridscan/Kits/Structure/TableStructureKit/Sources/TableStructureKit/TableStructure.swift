import Foundation

/// Geometry-only assembly of positioned text runs into blocks, visual rows, column bands and
/// a rectangular grid of text cells. Pure, stateless. No Vision types here — the app adapts
/// OCR observations into `TextRun` at the seam.
///
/// Coordinates: normalized page space, ORIGIN TOP-LEFT, y grows downward (rendered-image
/// convention). Adapters converting from PDF space (bottom-left origin) MUST flip y before
/// calling in — the mismatch mirrors layouts vertically without erroring (see PROMPT.md).
///
/// MODEL CAVEAT: heuristic layout clustering, validated against synthetic golden fixtures.
/// It is the OCR-fallback path only; Vision's RecognizeDocumentsRequest is the primary
/// table source and does not pass through this Kit's clustering.
public struct TextRun: Sendable, Equatable, Hashable {
    public var text: String
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double

    public init(_ text: String, minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.text = text
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    public var midX: Double { (minX + maxX) / 2 }
    public var midY: Double { (minY + maxY) / 2 }
    public var height: Double { maxY - minY }
}

public enum TableStructure {

    /// Cluster runs into visual rows. Runs are taken in vertical-centre order; a run joins the
    /// open row when its vertical overlap with the row's band is at least `overlap` of the
    /// smaller of (run height, band height). Each returned row is sorted left→right.
    public static func rows(of runs: [TextRun], overlap: Double = 0.5) -> [[TextRun]] {
        guard !runs.isEmpty else { return [] }
        let sorted = runs.sorted { $0.midY < $1.midY }
        var result: [[TextRun]] = []
        var current: [TextRun] = [sorted[0]]
        var bandMin = sorted[0].minY
        var bandMax = sorted[0].maxY
        for run in sorted.dropFirst() {
            let ov = min(bandMax, run.maxY) - max(bandMin, run.minY)
            let ref = min(run.height, bandMax - bandMin)
            if ref > 0, ov >= overlap * ref {
                current.append(run)
                bandMin = min(bandMin, run.minY)
                bandMax = max(bandMax, run.maxY)
            } else {
                result.append(current.sorted { $0.minX < $1.minX })
                current = [run]
                bandMin = run.minY
                bandMax = run.maxY
            }
        }
        result.append(current.sorted { $0.minX < $1.minX })
        return result
    }

    /// Merge the horizontal extents of every run into disjoint column bands, left→right.
    /// Extents closer than `tolerance` merge into one band.
    public static func columnBands(of rows: [[TextRun]], tolerance: Double = 0.0)
        -> [ClosedRange<Double>] {
        let intervals = rows.flatMap { $0 }.map { ($0.minX, $0.maxX) }.sorted { $0.0 < $1.0 }
        guard let first = intervals.first else { return [] }
        var bands: [(Double, Double)] = [first]
        for (lo, hi) in intervals.dropFirst() {
            if lo <= bands[bands.count - 1].1 + tolerance {
                bands[bands.count - 1].1 = max(bands[bands.count - 1].1, hi)
            } else {
                bands.append((lo, hi))
            }
        }
        return bands.map { $0.0...$0.1 }
    }

    /// Assign each run to the band containing its horizontal centre (nearest band if none
    /// contains it). Result is rectangular: rows.count × bands.count; runs within a cell are
    /// in x order. Consumers needing provenance use this; `grid` is the text-only view.
    public static func cellRuns(rows: [[TextRun]], bands: [ClosedRange<Double>]) -> [[[TextRun]]] {
        guard !bands.isEmpty else { return rows.map { _ in [] } }
        return rows.map { row in
            var cells: [[TextRun]] = Array(repeating: [], count: bands.count)
            for run in row {
                let idx = bands.firstIndex { $0.contains(run.midX) }
                    ?? bands.indices.min {
                        distance(from: run.midX, to: bands[$0])
                            < distance(from: run.midX, to: bands[$1])
                    }!
                cells[idx].append(run)
            }
            return cells.map { $0.sorted { $0.minX < $1.minX } }
        }
    }

    /// Text-only grid: runs sharing a cell join with a single space in x order; absent cells
    /// are the empty string.
    public static func grid(rows: [[TextRun]], bands: [ClosedRange<Double>]) -> [[String]] {
        cellRuns(rows: rows, bands: bands).map { row in
            row.map { $0.map(\.text).joined(separator: " ") }
        }
    }

    /// Split a row sequence into vertical blocks wherever the gap between consecutive rows
    /// exceeds `gapFactor` × the median row height. Prose paragraphs and tables on the same
    /// page separate here before any grid is attempted.
    public static func blocks(of rows: [[TextRun]], gapFactor: Double = 1.8) -> [[[TextRun]]] {
        guard !rows.isEmpty else { return [] }
        let bandsOf = rows.map { row -> (Double, Double) in
            (row.map(\.minY).min()!, row.map(\.maxY).max()!)
        }
        let heights = bandsOf.map { $0.1 - $0.0 }.sorted()
        let median = heights[heights.count / 2]
        var result: [[[TextRun]]] = [[rows[0]]]
        for i in 1..<rows.count {
            let gap = bandsOf[i].0 - bandsOf[i - 1].1
            if gap > gapFactor * median {
                result.append([rows[i]])
            } else {
                result[result.count - 1].append(rows[i])
            }
        }
        return result
    }

    /// Convenience: one rectangular grid from runs presumed to form a single block.
    public static func table(from runs: [TextRun]) -> [[String]] {
        let r = rows(of: runs)
        return grid(rows: r, bands: columnBands(of: r))
    }

    private static func distance(from x: Double, to band: ClosedRange<Double>) -> Double {
        if x < band.lowerBound { return band.lowerBound - x }
        if x > band.upperBound { return x - band.upperBound }
        return 0
    }
}
