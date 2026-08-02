import AppKit

// MARINE NAV icon glyph — a tide curve crossing chart datum, with the high-water
// mark called out. The same shape the app's hero screen draws, so the icon is
// literally the product.
//
// Rendered on a TRANSPARENT field: the .icon bundle's automatic gradient supplies
// the deep-navy body, shadow and translucency (Icon Composer, Xcode 26).
//
// Run: swift tools/genicon.swift <out.png>

let S: CGFloat = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8,
                    bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [r, g, b, a])!
}
let sea      = rgb(0.290, 0.847, 0.984)          // #4AD8FB — signal aqua
let seaHi    = rgb(0.560, 0.925, 1.000)
let seaLo    = rgb(0.150, 0.650, 0.850)
let foam     = rgb(0.290, 0.847, 0.984, 0.22)    // under-curve fill
let datum    = rgb(1.000, 1.000, 1.000, 0.55)    // chart-datum rule

ctx.clear(CGRect(x: 0, y: 0, width: S, height: S))

// ---- the tide curve -------------------------------------------------------
// One and a half cycles: a crest, a trough, a rising crest. Enough to read as a
// repeating tide, few enough strokes to stay legible at 16 pt.
let left: CGFloat = 116, right: CGFloat = 908
let mid: CGFloat = 512                    // chart datum
let amp: CGFloat = 232

func tideY(_ x: CGFloat) -> CGFloat {
    let t = (x - left) / (right - left)                 // 0…1
    return mid + amp * sin((t * 1.5 - 0.25) * 2 * .pi)
}

let curve = CGMutablePath()
curve.move(to: CGPoint(x: left, y: tideY(left)))
var x = left
while x <= right {
    curve.addLine(to: CGPoint(x: x, y: tideY(x)))
    x += 2
}

// chart datum — every US sounding is referenced to it (MLLW). Solid and BEHIND
// the curve: dashes at this scale disappear under the stroke and the fill.
ctx.setStrokeColor(datum)
ctx.setLineWidth(16)
ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: left, y: mid))
ctx.addLine(to: CGPoint(x: right, y: mid))
ctx.strokePath()

// water below the curve, faint, fading out downward
ctx.saveGState()
let under = CGMutablePath()
under.addPath(curve)
under.addLine(to: CGPoint(x: right, y: 168))
under.addLine(to: CGPoint(x: left, y: 168))
under.closeSubpath()
ctx.addPath(under); ctx.clip()
if let g = CGGradient(colorsSpace: cs, colors: [foam, rgb(0.290, 0.847, 0.984, 0.02)] as CFArray,
                      locations: [0, 1]) {
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: mid + amp),
                           end: CGPoint(x: 0, y: 168), options: [])
}
ctx.restoreGState()

// the curve itself — thick, gradient-lit, round caps, drawn last so it wins
ctx.saveGState()
ctx.addPath(curve)
ctx.setLineWidth(72)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.replacePathWithStrokedPath()
ctx.clip()
if let grad = CGGradient(colorsSpace: cs, colors: [seaHi, sea, seaLo] as CFArray,
                         locations: [0, 0.5, 1]) {
    ctx.drawLinearGradient(grad, start: CGPoint(x: left, y: mid + amp),
                           end: CGPoint(x: right, y: mid - amp), options: [])
}
ctx.restoreGState()

// ---- write ----------------------------------------------------------------
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
guard let image = ctx.makeImage() else { fatalError("no image") }
let rep = NSBitmapImageRep(cgImage: image)
rep.size = NSSize(width: S, height: S)
guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("no png") }
try! data.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
