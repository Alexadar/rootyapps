// Generates the born-digital fixture PDF for the end-to-end import UITest:
// a small 3-column table drawn with CoreText (real selectable text layer).
// Run: swift tools/make_fixture_pdf.swift gridscanUITests/Fixtures/table.pdf
import Foundation
import CoreGraphics
import CoreText

let out = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "gridscanUITests/Fixtures/table.pdf"
let url = URL(fileURLWithPath: out)
try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                         withIntermediateDirectories: true)

var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
guard let ctx = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
    fatalError("no pdf context")
}
ctx.beginPDFPage(nil)

func draw(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat = 12, bold: Bool = false) {
    let font = CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString,
                                    size, nil)
    let attr = [kCTFontAttributeName: font] as CFDictionary
    let str = CFAttributedStringCreate(nil, text as CFString, attr)!
    let line = CTLineCreateWithAttributedString(str)
    ctx.textPosition = CGPoint(x: x, y: y)
    CTLineDraw(line, ctx)
}

// Rows spaced widely so word clustering is unambiguous. Non-commerce content.
draw("Field observations", x: 72, y: 720, size: 18, bold: true)
let cols: [CGFloat] = [72, 250, 420]
let header = ["Plot", "Species", "Count"]
let rows = [
    ["N-01", "willow warbler", "4"],
    ["N-02", "reed bunting", "2"],
    ["N-03", "sedge warbler", "7"],
]
for (c, h) in header.enumerated() { draw(h, x: cols[c], y: 660, bold: true) }
for (r, row) in rows.enumerated() {
    for (c, cell) in row.enumerated() {
        draw(cell, x: cols[c], y: 660 - CGFloat(r + 1) * 28)
    }
}
draw("Recorded at first light, wind calm.", x: 72, y: 480)

ctx.endPDFPage()
ctx.closePDF()
print("wrote \(out)")
