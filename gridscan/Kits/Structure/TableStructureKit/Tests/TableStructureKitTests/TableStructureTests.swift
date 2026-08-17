import Testing
import Foundation
@testable import TableStructureKit

/// Oracle = constructed golden fixtures: synthetic layouts with known ground-truth structure
/// (top-left origin, y downward). Values chosen so correct clustering is unambiguous.
@Suite struct TableStructureTests {

    /// A run one text-line high (0.02) at row r, column band c, with vertical jitter.
    private func run(_ text: String, row r: Int, col c: Int, jitter: Double = 0.0) -> TextRun {
        let y = 0.1 + Double(r) * 0.05 + jitter
        let x = 0.1 + Double(c) * 0.25
        return TextRun(text, minX: x, minY: y, maxX: x + 0.18, maxY: y + 0.02)
    }

    @Test func threeByThreeGridWithJitter() {
        let runs = [
            run("Name", row: 0, col: 0), run("Qty", row: 0, col: 1, jitter: 0.004), run("Note", row: 0, col: 2),
            run("bolt", row: 1, col: 0, jitter: -0.003), run("12", row: 1, col: 1), run("zinc", row: 1, col: 2, jitter: 0.005),
            run("nut", row: 2, col: 0), run("8", row: 2, col: 1, jitter: 0.002), run("steel", row: 2, col: 2),
        ].shuffled()
        #expect(TableStructure.table(from: runs) == [
            ["Name", "Qty", "Note"],
            ["bolt", "12", "zinc"],
            ["nut", "8", "steel"],
        ])
    }

    @Test func missingCellBecomesEmptyString() {
        let runs = [
            run("a", row: 0, col: 0), run("b", row: 0, col: 1),
            run("c", row: 1, col: 0), /* (1,1) absent */
            run("d", row: 2, col: 0), run("e", row: 2, col: 1),
        ]
        #expect(TableStructure.table(from: runs) == [["a", "b"], ["c", ""], ["d", "e"]])
    }

    @Test func multipleRunsInOneCellJoinInXOrder() {
        var runs = [run("total", row: 0, col: 0), run("x", row: 0, col: 1)]
        // Second fragment inside column band 0, to the right of "total".
        runs.append(TextRun("due", minX: 0.20, minY: 0.1, maxX: 0.27, maxY: 0.12))
        let grid = TableStructure.table(from: runs)
        #expect(grid == [["total due", "x"]])
    }

    @Test func blocksSplitOnLargeVerticalGap() {
        // Three tight rows, a gap of 5 line-heights, then two more rows.
        var runs: [TextRun] = []
        for r in 0..<3 { runs.append(run("t\(r)", row: r, col: 0)) }
        for r in 0..<2 {
            let y = 0.5 + Double(r) * 0.05
            runs.append(TextRun("p\(r)", minX: 0.1, minY: y, maxX: 0.4, maxY: y + 0.02))
        }
        let rows = TableStructure.rows(of: runs)
        let blocks = TableStructure.blocks(of: rows)
        #expect(blocks.count == 2)
        #expect(blocks[0].count == 3)
        #expect(blocks[1].count == 2)
    }

    @Test func overlappingExtentsMergeIntoOneBand() {
        // Two runs whose x extents overlap belong to one column band, not two.
        let a = TextRun("left", minX: 0.10, minY: 0.10, maxX: 0.30, maxY: 0.12)
        let b = TextRun("wide", minX: 0.25, minY: 0.15, maxX: 0.60, maxY: 0.17)
        let rows = TableStructure.rows(of: [a, b])
        #expect(rows.count == 2)
        #expect(TableStructure.columnBands(of: rows).count == 1)
    }

    @Test func emptyInput() {
        #expect(TableStructure.rows(of: []).isEmpty)
        #expect(TableStructure.table(from: []).isEmpty)
        #expect(TableStructure.blocks(of: []).isEmpty)
        #expect(TableStructure.columnBands(of: []).isEmpty)
    }

    @Test func cellRunsPreserveProvenanceSources() {
        // cellRuns is grid's provenance-carrying twin: same assignment, runs not joined.
        let runs = [
            run("a", row: 0, col: 0), run("b", row: 0, col: 1),
            run("c", row: 1, col: 0),
        ]
        let rows = TableStructure.rows(of: runs)
        let bands = TableStructure.columnBands(of: rows)
        let cells = TableStructure.cellRuns(rows: rows, bands: bands)
        #expect(cells.count == 2 && cells[0].count == 2)
        #expect(cells[0][0].map(\.text) == ["a"])
        #expect(cells[1][1].isEmpty)
        // Consistency with the text grid.
        #expect(TableStructure.grid(rows: rows, bands: bands)
            == cells.map { $0.map { $0.map(\.text).joined(separator: " ") } })
    }

    @Test func rowsAreSortedLeftToRightRegardlessOfInputOrder() {
        let runs = [run("c", row: 0, col: 2), run("a", row: 0, col: 0), run("b", row: 0, col: 1)]
        let rows = TableStructure.rows(of: runs)
        #expect(rows.count == 1)
        #expect(rows[0].map(\.text) == ["a", "b", "c"])
    }
}
