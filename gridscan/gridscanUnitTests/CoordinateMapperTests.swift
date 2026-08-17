import XCTest
import CoreGraphics
import DocumentModelKit
@testable import GridScan

/// The y-flip is the PROMPT.md trap: PDF is bottom-left origin, the model is top-left.
/// Getting it wrong mirrors every layout vertically without erroring — so it gets its
/// own oracle tests with hand-computed values.
final class CoordinateMapperTests: XCTestCase {

    func testPDFBottomLeftFlipsToTopLeft() {
        // Page 100×200 (PDF points). A word near the TOP of the page has a LARGE PDF y.
        let cropBox = CGRect(x: 0, y: 0, width: 100, height: 200)
        let wordNearTop = CGRect(x: 10, y: 180, width: 20, height: 10)   // PDF: top edge at y=190
        let prov = CoordinateMapper.bboxFromPDF(wordNearTop, cropBox: cropBox, pageIndex: 3)
        XCTAssertEqual(prov.pageIndex, 3)
        XCTAssertEqual(prov.bbox.origin, .topLeft)
        XCTAssertEqual(prov.bbox.x, 0.10, accuracy: 1e-9)
        XCTAssertEqual(prov.bbox.y, 0.05, accuracy: 1e-9)     // (200-190)/200 from the top
        XCTAssertEqual(prov.bbox.width, 0.20, accuracy: 1e-9)
        XCTAssertEqual(prov.bbox.height, 0.05, accuracy: 1e-9)
    }

    func testCropBoxOffsetIsRespected() {
        // Crop boxes do not start at (0,0) in real PDFs.
        let cropBox = CGRect(x: 50, y: 100, width: 100, height: 200)
        let word = CGRect(x: 50, y: 100, width: 100, height: 200)        // exactly the crop box
        let bbox = CoordinateMapper.bboxFromPDF(word, cropBox: cropBox, pageIndex: 0).bbox
        XCTAssertEqual(bbox.x, 0, accuracy: 1e-9)
        XCTAssertEqual(bbox.y, 0, accuracy: 1e-9)
        XCTAssertEqual(bbox.width, 1, accuracy: 1e-9)
        XCTAssertEqual(bbox.height, 1, accuracy: 1e-9)
    }

    func testRoundTripThroughTextRun() {
        let prov = Provenance(pageIndex: 1,
                              bbox: BBox(x: 0.2, y: 0.3, width: 0.1, height: 0.05,
                                         origin: .topLeft))
        let run = CoordinateMapper.textRun("x", prov: prov)
        let back = CoordinateMapper.provenance(of: run, pageIndex: 1)
        XCTAssertEqual(back.bbox.x, prov.bbox.x, accuracy: 1e-9)
        XCTAssertEqual(back.bbox.y, prov.bbox.y, accuracy: 1e-9)
        XCTAssertEqual(back.bbox.width, prov.bbox.width, accuracy: 1e-9)
        XCTAssertEqual(back.bbox.height, prov.bbox.height, accuracy: 1e-9)
    }
}
