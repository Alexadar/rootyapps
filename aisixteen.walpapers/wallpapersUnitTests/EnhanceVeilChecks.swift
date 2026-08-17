import XCTest
@testable import Wallpapers

/// ORACLES:
///  • INVARIANT — the cells exactly tile the rect: no gap, no overlap, nothing outside it. A gap is
///    a stripe of picture that never clears; an overlap double-darkens a seam.
///  • INVARIANT — cells come back in working order, left to right then top to bottom, matching
///    `TileRefiner.grid`. Any other order clears the wrong square and the indicator stops being
///    spatially true — which is the entire idea.
///  • BEHAVIOUR — the partition follows the real tile count, not the number three. The design's
///    prose says 3×3 because a 1024² working size is nine tiles; a different total must still
///    produce a sane grid rather than a wrong one.
final class EnhanceVeilChecks: XCTestCase {

    func testNineTilesAreThreeByThree() {
        // What the app actually does: a 2048² master refined at 1024², nine tiles.
        let grid = EnhanceVeilGrid.partition(total: 9)
        XCTAssertEqual(grid.columns, 3)
        XCTAssertEqual(grid.rows, 3)
        XCTAssertEqual(TileRefiner.grid(width: TileRefiner.workingSide,
                                        height: TileRefiner.workingSide).count, 9,
                       "the veil's 3×3 must match the refiner's real tile count")
    }

    func testThePartitionFollowsTheTileCountNotTheNumberThree() {
        // The x axis is always the fixed 1024 working side, so three columns holds — but the total
        // is what decides the rows. A twelve-tile job is 3×4, not 3×3 with three tiles unaccounted.
        XCTAssertEqual(EnhanceVeilGrid.partition(total: 12).columns, 3)
        XCTAssertEqual(EnhanceVeilGrid.partition(total: 12).rows, 4)
        XCTAssertEqual(EnhanceVeilGrid.partition(total: 1).columns, 1)
        XCTAssertEqual(EnhanceVeilGrid.partition(total: 1).rows, 1)

        // Anything not divisible by three degrades to a near-square grid that still covers.
        for total in [2, 4, 5, 7, 8, 10, 11, 16, 25] {
            let grid = EnhanceVeilGrid.partition(total: total)
            XCTAssertGreaterThanOrEqual(grid.columns * grid.rows, total,
                                        "a \(total)-tile job has cells it cannot show")
        }
    }

    func testTheCellsExactlyTileTheRect() {
        let rect = CGRect(x: 12, y: 40, width: 300, height: 540)
        let cells = EnhanceVeilGrid.cells(in: rect, columns: 3, rows: 3)
        XCTAssertEqual(cells.count, 9)

        let area = cells.reduce(0) { $0 + $1.width * $1.height }
        XCTAssertEqual(area, rect.width * rect.height, accuracy: 0.01, "the cells do not tile")

        let union = cells.dropFirst().reduce(cells[0]) { $0.union($1) }
        XCTAssertEqual(union.minX, rect.minX, accuracy: 0.01)
        XCTAssertEqual(union.minY, rect.minY, accuracy: 0.01)
        XCTAssertEqual(union.maxX, rect.maxX, accuracy: 0.01)
        XCTAssertEqual(union.maxY, rect.maxY, accuracy: 0.01)
    }

    func testTheCellsAreInWorkingOrder() {
        // Left to right, top to bottom — the order `TileRefiner.grid` walks. `done == k` means the
        // first k of these are complete, so a different order clears the wrong squares.
        let cells = EnhanceVeilGrid.cells(in: CGRect(x: 0, y: 0, width: 300, height: 300),
                                          columns: 3, rows: 3)
        XCTAssertEqual(cells[0].minX, 0);   XCTAssertEqual(cells[0].minY, 0)
        XCTAssertEqual(cells[1].minX, 100); XCTAssertEqual(cells[1].minY, 0)
        XCTAssertEqual(cells[2].minX, 200); XCTAssertEqual(cells[2].minY, 0)
        XCTAssertEqual(cells[3].minX, 0);   XCTAssertEqual(cells[3].minY, 100)
        XCTAssertEqual(cells[8].minX, 200); XCTAssertEqual(cells[8].minY, 200)

        let refiner = TileRefiner.grid(width: 1024, height: 1024)
        XCTAssertEqual(refiner.map(\.y), refiner.map(\.y).sorted(),
                       "the refiner walks rows in order, which is what the veil assumes")
    }

    func testAFittedPortraitInALandscapeContainerIsLetterboxed() {
        // The Gallery sheet uses `.scaledToFit()`. Veiling the container instead of the picture
        // would draw cells over the empty bars.
        let rect = EnhanceVeilGrid.fittedRect(imageSize: CGSize(width: 1000, height: 2000),
                                              in: CGSize(width: 400, height: 400))
        XCTAssertEqual(rect.width, 200, accuracy: 0.01)
        XCTAssertEqual(rect.height, 400, accuracy: 0.01)
        XCTAssertEqual(rect.minX, 100, accuracy: 0.01, "centred horizontally")
        XCTAssertEqual(rect.minY, 0, accuracy: 0.01)
    }

    func testAFittedLandscapeInAPortraitContainerIsLetterboxedTheOtherWay() {
        let rect = EnhanceVeilGrid.fittedRect(imageSize: CGSize(width: 2000, height: 1000),
                                              in: CGSize(width: 400, height: 400))
        XCTAssertEqual(rect.width, 400, accuracy: 0.01)
        XCTAssertEqual(rect.height, 200, accuracy: 0.01)
        XCTAssertEqual(rect.minY, 100, accuracy: 0.01)
    }

    func testASquareMasterInASquareContainerFillsIt() {
        let rect = EnhanceVeilGrid.fittedRect(imageSize: CGSize(width: 2048, height: 2048),
                                              in: CGSize(width: 300, height: 300))
        XCTAssertEqual(rect, CGRect(x: 0, y: 0, width: 300, height: 300))
    }

    func testDegenerateSizesDoNotCrashOrDivideByZero() {
        XCTAssertEqual(EnhanceVeilGrid.fittedRect(imageSize: .zero,
                                                  in: CGSize(width: 100, height: 100)),
                       CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertTrue(EnhanceVeilGrid.cells(in: .zero, columns: 0, rows: 0).isEmpty)
    }
}
