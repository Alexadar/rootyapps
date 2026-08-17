import Foundation
import PDFKit
import CoreGraphics

/// Renders a scanned/garbage-layer PDF page for OCR at ~300 DPI. The 72-pt default
/// render is the documented trap — it destroys recognition accuracy.
enum PDFPageRenderer {

    static func render(page: PDFPage, dpi: CGFloat = ExtractionTuning.renderDPI) -> CGImage? {
        let cropBox = page.bounds(for: .cropBox)
        guard cropBox.width > 0, cropBox.height > 0 else { return nil }
        let scale = dpi / 72.0
        let width = Int(cropBox.width * scale)
        let height = Int(cropBox.height * scale)
        guard width > 0, height > 0,
              let ctx = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -cropBox.minX, y: -cropBox.minY)
        page.draw(with: .cropBox, to: ctx)
        return ctx.makeImage()
    }
}
