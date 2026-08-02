import AppKit

// KERF icon glyph — modern take: a bold, round-cornered speed-square (signal) with a single kerf
// slot cut through it, on a TRANSPARENT field (the .icon gradient supplies the graphite body).
// Run: swift tools/genicon.swift <out.png>

let S: CGFloat = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8,
                    bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [r, g, b, a])!
}
let signal = rgb(0.910, 0.984, 0.290)   // #E8FB4A
let signalHi = rgb(0.965, 1.000, 0.560)
let signalLo = rgb(0.760, 0.850, 0.150)
let ink = rgb(0.086, 0.090, 0.106)       // #16171B graphite

ctx.clear(CGRect(x: 0, y: 0, width: S, height: S))

// A round-cornered right triangle. Right angle at bottom-right (b); hypotenuse a→c ascends.
let a = CGPoint(x: 232, y: 348)   // bottom-left
let b = CGPoint(x: 726, y: 348)   // bottom-right (right angle)
let c = CGPoint(x: 726, y: 842)   // top-right
let r: CGFloat = 62

func roundedTri(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ rad: CGFloat) -> CGPath {
    let m = CGPoint(x: (p2.x + p0.x) / 2, y: (p2.y + p0.y) / 2)
    let path = CGMutablePath()
    path.move(to: m)
    path.addArc(tangent1End: p0, tangent2End: p1, radius: rad)
    path.addArc(tangent1End: p1, tangent2End: p2, radius: rad)
    path.addArc(tangent1End: p2, tangent2End: p0, radius: rad)
    path.closeSubpath()
    return path
}
let tri = roundedTri(a, b, c, r)

// body — signal, soft vertical gradient for depth
ctx.saveGState()
ctx.addPath(tri); ctx.clip()
if let grad = CGGradient(colorsSpace: cs, colors: [signalHi, signal, signalLo] as CFArray, locations: [0, 0.55, 1]) {
    ctx.drawLinearGradient(grad, start: CGPoint(x: 232, y: 900), end: CGPoint(x: 726, y: 300), options: [])
}
ctx.restoreGState()

// kerf slot — a single clean cut parallel to the hypotenuse, punched out of the body.
// hypotenuse direction a→c; offset a thin capsule inward (toward the right angle).
ctx.saveGState()
ctx.addPath(tri); ctx.clip()                       // keep the cut inside the triangle
let dx = c.x - a.x, dy = c.y - a.y
let len = (dx * dx + dy * dy).squareRoot()
let nx = dy / len, ny = -dx / len                  // unit normal
let off: CGFloat = 96                               // inward offset from the hypotenuse
let p1 = CGPoint(x: a.x - nx * off, y: a.y - ny * off)
let p2 = CGPoint(x: c.x - nx * off, y: c.y - ny * off)
let slot = CGMutablePath()
slot.move(to: p1); slot.addLine(to: p2)
ctx.setStrokeColor(ink)
ctx.setLineWidth(30)
ctx.setLineCap(.round)
ctx.addPath(slot); ctx.strokePath()
ctx.restoreGState()

// right-angle square mark inside the corner (b) — the precision cue
let sqSize: CGFloat = 60
ctx.setStrokeColor(ink.copy(alpha: 0.55)!)
ctx.setLineWidth(12)
let sq = CGMutablePath()
sq.move(to: CGPoint(x: b.x - 22 - sqSize, y: b.y + 22))
sq.addLine(to: CGPoint(x: b.x - 22 - sqSize, y: b.y + 22 + sqSize))
sq.addLine(to: CGPoint(x: b.x - 22, y: b.y + 22 + sqSize))
ctx.addPath(sq); ctx.strokePath()

guard let img = ctx.makeImage() else { fatalError("no image") }
let rep = NSBitmapImageRep(cgImage: img)
let png = rep.representation(using: .png, properties: [:])!
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
