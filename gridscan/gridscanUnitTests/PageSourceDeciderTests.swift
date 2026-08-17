import XCTest
import CoreGraphics
@testable import GridScan

/// Golden tests for the per-page text-layer-vs-OCR branch. The trap under test:
/// a usable text layer is NOT `string != nil` — bad prior OCR leaves a garbage layer.
final class PageSourceDeciderTests: XCTestCase {

    private let cropBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    private func bounds(_ n: Int) -> [CGRect] {
        (0..<n).map { CGRect(x: 40 + Double($0 % 8) * 60,
                             y: 700 - Double($0 / 8) * 20, width: 50, height: 12) }
    }

    func testCleanBornDigitalTextIsTextLayer() {
        let text = """
        Sample ID Depth pH Moisture collected during the spring survey of plot seven.
        Values recorded in the field notebook and transcribed the same afternoon.
        """
        XCTAssertEqual(PageSourceDecider.decide(text: text, wordBounds: bounds(24),
                                                cropBox: cropBox), .textLayer)
    }

    func testMissingTextLayerGoesToOCR() {
        XCTAssertEqual(PageSourceDecider.decide(text: nil, wordBounds: [], cropBox: cropBox),
                       .ocr(.noTextLayer))
        XCTAssertEqual(PageSourceDecider.decide(text: "  \n ", wordBounds: [], cropBox: cropBox),
                       .ocr(.noTextLayer))
        XCTAssertEqual(PageSourceDecider.decide(text: "short", wordBounds: [], cropBox: cropBox),
                       .ocr(.noTextLayer))
    }

    func testReplacementCharactersMeanGarbage() {
        let text = String(repeating: "word ", count: 20)
            + String(repeating: "\u{FFFD}", count: 3)
        XCTAssertEqual(PageSourceDecider.decide(text: text, wordBounds: bounds(20),
                                                cropBox: cropBox), .ocr(.garbageLayer))
    }

    func testSymbolSoupMeansGarbage() {
        // Prior-OCR junk: mostly non-alphanumeric tokens.
        let text = "~~ ]] |= )( ** ## }{ ;; :: ~~ ]] |= )( ** ## }{ ;; :: word two three"
        XCTAssertEqual(PageSourceDecider.decide(text: text, wordBounds: bounds(20),
                                                cropBox: cropBox), .ocr(.garbageLayer))
    }

    func testShatteredSingleCharTokensMeanGarbage() {
        // The classic bad-OCR signature: words shattered into single letters.
        let text = "T h e q u i c k b r o w n f o x j u m p s o v e r t h e l a z y d o g"
        XCTAssertEqual(PageSourceDecider.decide(text: text, wordBounds: bounds(30),
                                                cropBox: cropBox), .ocr(.garbageLayer))
    }

    func testDegenerateBoundsMeanGarbage() {
        let text = String(repeating: "plausible words with normal shape here ", count: 5)
        let degenerate = (0..<20).map { _ in CGRect(x: -5000, y: -5000, width: 0, height: 0) }
        XCTAssertEqual(PageSourceDecider.decide(text: text, wordBounds: degenerate,
                                                cropBox: cropBox), .ocr(.garbageLayer))
    }

    func testStampOnFullPageScanGoesToOCR() {
        // Tiny text coverage + short text = a header/stamp on a scanned image.
        let text = "RECEIVED 14 MAR FILE COPY department of records"
        let tiny = (0..<6).map { CGRect(x: 40 + Double($0) * 20, y: 770, width: 6, height: 4) }
        XCTAssertEqual(PageSourceDecider.decide(text: text, wordBounds: tiny,
                                                cropBox: cropBox), .ocr(.imageWithTokenText))
    }
}
