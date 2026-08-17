#!/usr/bin/env swift
//
// Renders the app icon: a 1024 px square of exactly what the app makes.
//
// The icon is a wallpaper. Not a picture *of* a wallpaper, not a camera glyph, not a sparkle on a
// gradient — one real output of the same kind of seeded colour field the app generates, at icon
// size. It says what the app does without a metaphor, and it cannot go out of date with the UI.
//
// Deterministic: the seed is fixed, so re-running this produces a byte-identical PNG and the icon
// never drifts between builds.
//
//   swift tools/make_icon.swift wallpapers.icon/Assets/1024.png
//
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// SplitMix64 — same generator the app uses, so the icon is drawn from the same distribution as a
// real wallpaper rather than from an unrelated one.
struct Seeded: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

func hsb(_ h: Double, _ s: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    let sector = (h.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * 6
    let i = Int(sector), f = sector - Double(i)
    let p = b * (1 - s), q = b * (1 - s * f), t = b * (1 - s * (1 - f))
    let (r, g, bl): (Double, Double, Double)
    switch i % 6 {
    case 0: (r, g, bl) = (b, t, p)
    case 1: (r, g, bl) = (q, b, p)
    case 2: (r, g, bl) = (p, b, t)
    case 3: (r, g, bl) = (p, q, b)
    case 4: (r, g, bl) = (t, p, b)
    default: (r, g, bl) = (b, p, q)
    }
    return CGColor(srgbRed: r, green: g, blue: bl, alpha: a)
}

let side = 1024
let space = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: side, height: side,
                          bitsPerComponent: 8, bytesPerRow: side * 4,
                          space: space,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("could not create the drawing context")
}

var rng = Seeded(seed: 0x1651_2016)

// A deep blue-violet ground, so the accent reads as light coming through rather than as paint.
ctx.setFillColor(hsb(0.66, 0.55, 0.13))
ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))

// **Two** blooms, not four.
//
// The first attempt used four hues spread across the square and it read as mud at 60 px, which is
// the size that actually matters. An icon has one composition and needs one legible gesture: a cool
// light in one corner, a warm one in the opposite corner, and a clear diagonal between them. The
// violet where they meet is a consequence of the two, not a third colour placed by hand.
let blooms: [(x: Double, y: Double, r: Double, colour: CGColor, peak: Double)] = [
    (0.26, 0.78, 0.66, hsb(0.60, 0.90, 1.00), 0.95),   // accent blue, upper left
    (0.76, 0.24, 0.62, hsb(0.06, 0.85, 1.00), 0.90),   // warm amber, lower right
]

for bloom in blooms {
    let centre = CGPoint(x: bloom.x * Double(side), y: bloom.y * Double(side))
    guard let gradient = CGGradient(colorsSpace: space,
                                    colors: [bloom.colour.copy(alpha: bloom.peak)!,
                                             bloom.colour.copy(alpha: 0)!] as CFArray,
                                    // Held near full strength through the middle third, so each
                                    // bloom has a solid core instead of dissolving immediately.
                                    locations: [0.18, 1]) else { continue }
    ctx.drawRadialGradient(gradient,
                           startCenter: centre, startRadius: 0,
                           endCenter: centre, endRadius: bloom.r * Double(side),
                           options: [])
}

// A vignette. Gives the square depth and, more practically, keeps the bright edges off the
// squircle's clip — a bloom running flat into the corner reads as a cropped photograph.
if let vignette = CGGradient(colorsSpace: space,
                             colors: [CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0),
                                      CGColor(srgbRed: 0.02, green: 0.02, blue: 0.07, alpha: 0.55)] as CFArray,
                             locations: [0.45, 1]) {
    let centre = CGPoint(x: Double(side) / 2, y: Double(side) / 2)
    ctx.drawRadialGradient(vignette,
                           startCenter: centre, startRadius: 0,
                           endCenter: centre, endRadius: Double(side) * 0.78,
                           options: [])
}

// The grain that keeps it from looking like a stock gradient — generated small and scaled up, the
// same trick the app's renderer uses.
let small = 128
var noise = [UInt8](repeating: 0, count: small * small * 4)
for i in stride(from: 0, to: noise.count, by: 4) {
    let v = UInt8(Double.random(in: 0...255, using: &rng))
    noise[i] = v; noise[i + 1] = v; noise[i + 2] = v; noise[i + 3] = 255
}
if let provider = CGDataProvider(data: Data(noise) as CFData),
   let grain = CGImage(width: small, height: small, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: small * 4, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil,
                       shouldInterpolate: true, intent: .defaultIntent) {
    ctx.saveGState()
    ctx.setAlpha(0.10)
    ctx.setBlendMode(.overlay)
    ctx.interpolationQuality = .high
    ctx.draw(grain, in: CGRect(x: 0, y: 0, width: side, height: side))
    ctx.restoreGState()
}

guard let image = ctx.makeImage() else { fatalError("could not render") }

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "wallpapers.icon/Assets/1024.png"
let url = URL(fileURLWithPath: outputPath)
try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                         withIntermediateDirectories: true)

guard let destination = CGImageDestinationCreateWithURL(url as CFURL,
                                                        UTType.png.identifier as CFString, 1, nil) else {
    fatalError("could not open \(outputPath) for writing")
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(outputPath)") }
print("wrote \(outputPath)")
