import Foundation
import CoreGraphics
import Vision
import DocumentModelKit
import TableStructureKit

/// THE one place that flips y. Everything downstream of these functions is normalized
/// TOP-LEFT space (y grows downward) — TableStructureKit's hard requirement and the
/// space stored page renders use, so ReviewView highlights need no further transform.
/// PDF points are BOTTOM-LEFT; classic Vision normalized space is lower-left; the new
/// Swift Vision API converts explicitly via toImageCoordinates(_:origin:.upperLeft)
/// (verified against the iOS 26.5 swiftinterface).
enum CoordinateMapper {

    /// New-Vision region → normalized top-left BBox.
    @available(iOS 26.0, macOS 26.0, *)
    static func bbox(_ region: NormalizedRegion, pageIndex: Int) -> Provenance {
        let r = region.boundingBox.toImageCoordinates(CGSize(width: 1, height: 1),
                                                      origin: .upperLeft)
        return Provenance(pageIndex: pageIndex, bbox: clamped(r))
    }

    /// New-Vision rect → normalized top-left BBox.
    static func bbox(_ rect: NormalizedRect, pageIndex: Int) -> Provenance {
        let r = rect.toImageCoordinates(CGSize(width: 1, height: 1), origin: .upperLeft)
        return Provenance(pageIndex: pageIndex, bbox: clamped(r))
    }

    /// PDF-point rect (bottom-left origin, cropBox space) → normalized top-left BBox.
    static func bboxFromPDF(_ rect: CGRect, cropBox: CGRect, pageIndex: Int) -> Provenance {
        guard cropBox.width > 0, cropBox.height > 0 else {
            return Provenance(pageIndex: pageIndex,
                              bbox: BBox(x: 0, y: 0, width: 0, height: 0, origin: .topLeft))
        }
        let x = (rect.minX - cropBox.minX) / cropBox.width
        let w = rect.width / cropBox.width
        let h = rect.height / cropBox.height
        // Flip: PDF measures y up from the bottom; the model wants distance from the top.
        let y = (cropBox.maxY - rect.maxY) / cropBox.height
        return Provenance(pageIndex: pageIndex,
                          bbox: clamped(CGRect(x: x, y: y, width: w, height: h)))
    }

    static func textRun(_ text: String, prov: Provenance) -> TextRun {
        TextRun(text,
                minX: prov.bbox.x, minY: prov.bbox.y,
                maxX: prov.bbox.x + prov.bbox.width,
                maxY: prov.bbox.y + prov.bbox.height)
    }

    static func provenance(of run: TextRun, pageIndex: Int) -> Provenance {
        Provenance(pageIndex: pageIndex,
                   bbox: BBox(x: run.minX, y: run.minY,
                              width: run.maxX - run.minX, height: run.maxY - run.minY,
                              origin: .topLeft))
    }

    private static func clamped(_ r: CGRect) -> BBox {
        BBox(x: max(0, min(1, r.minX)), y: max(0, min(1, r.minY)),
             width: max(0, min(1, r.width)), height: max(0, min(1, r.height)),
             origin: .topLeft)
    }
}
