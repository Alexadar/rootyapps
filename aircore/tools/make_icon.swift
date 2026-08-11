#!/usr/bin/env swift
//
//  AirCore app icon.
//
//  Run:  swift tools/make_icon.swift
//
//  ## What it draws, and why
//
//  The saturation curve of a psychrometric chart, on deep water, with one state point under it.
//
//  That curve is the app. It is the boundary between air and fog, it is the line every other value
//  on the chart is measured against, and it is the thing the whole product is built to compute
//  correctly — the design scaffold this app grew from got it wrong by 19 % below freezing.
//
//  So it is drawn from the physics, not sketched: the path below is the Hyland–Wexler saturation
//  pressure at sea level, the same correlation `PsychroKit` ships, evaluated at 0.25 °C steps. The
//  three faint curves behind it are 30, 50 and 70 % relative humidity from the same equations.
//
//  Palette is water-breeze, from `DesignShared/Theme.swift`. No text, no gloss, no gradient tricks
//  — an instrument, not a poster. Nothing in it implies certification or any standards body.
//
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - The physics, so the curve is the real one

/// Hyland & Wexler (1983), over ice below 0 °C and water at or above it. Pa.
func saturationPressure(dryBulb t: Double) -> Double {
    let T = t + 273.15
    let ln: Double
    if t < 0 {
        ln = -5.6745359e3 / T + 6.3925247 - 9.677843e-3 * T + 6.2215701e-7 * T * T
            + 2.0747825e-9 * T * T * T - 9.484024e-13 * T * T * T * T + 4.1635019 * log(T)
    } else {
        ln = -5.8002206e3 / T + 1.3914993 - 4.8640239e-2 * T + 4.1764768e-5 * T * T
            - 1.4452093e-8 * T * T * T + 6.5459673 * log(T)
    }
    return exp(ln)
}

let seaLevel = 101_325.0

func humidityRatio(dryBulb t: Double, relativeHumidity rh: Double) -> Double {
    let pw = rh * saturationPressure(dryBulb: t)
    return 0.621945 * pw / (seaLevel - pw)
}

// MARK: - Colour

func colour(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

let deepWater = colour(0x0A2135)     // ground, top
let deepWater2 = colour(0x123F5E)    // ground, bottom
let breeze = colour(0xF0F7FB)        // the saturation curve
let working = colour(0x1288D4)       // the state point
let faint = colour(0x6FB9E6, 0.28)   // the RH curves behind it

// MARK: - Drawing

/// Chart bounds. Chosen so the saturation curve enters at the left edge and leaves through the
/// top, sweeping corner to corner — the shape reads at 40 points as well as at 1024.
let minDryBulb = -12.0
let maxDryBulb = 42.0
let maxHumidityRatio = 0.030

func drawIcon(size: CGFloat, context: CGContext) {
    // Full bleed. An inset plot rectangle leaves the filled region floating inside the icon with
    // visible straight edges, which reads as a screenshot of a chart rather than as a mark. The
    // curve runs off the left edge and out through the top, and the system mask does the framing.
    let plot = CGRect(x: 0, y: 0, width: size, height: size)

    func x(_ t: Double) -> CGFloat {
        plot.minX + CGFloat((t - minDryBulb) / (maxDryBulb - minDryBulb)) * plot.width
    }
    func y(_ w: Double) -> CGFloat {
        plot.minY + CGFloat(min(w, maxHumidityRatio) / maxHumidityRatio) * plot.height
    }

    // Ground: a vertical gradient, deeper at the top, the way water is.
    let space = CGColorSpaceCreateDeviceRGB()
    if let gradient = CGGradient(colorsSpace: space,
                                 colors: [deepWater2, deepWater] as CFArray,
                                 locations: [0, 1]) {
        context.drawLinearGradient(gradient,
                                   start: CGPoint(x: 0, y: 0),
                                   end: CGPoint(x: 0, y: size),
                                   options: [])
    }

    /// The curve, carried right up to the top edge.
    ///
    /// Stopping at the last sample *below* the top leaves the path a fraction of a percent short,
    /// which shows up as a dark notch in the top-right corner once the region under it is filled.
    /// So the crossing point is interpolated and the path ends exactly on the edge.
    func curve(relativeHumidity: Double) -> CGMutablePath {
        let path = CGMutablePath()
        var started = false
        var previous: (t: Double, w: Double)?
        var t = minDryBulb
        while t <= maxDryBulb {
            let w = humidityRatio(dryBulb: t, relativeHumidity: relativeHumidity)
            if w > maxHumidityRatio {
                if let previous {
                    let fraction = (maxHumidityRatio - previous.w) / (w - previous.w)
                    let crossing = previous.t + fraction * (t - previous.t)
                    path.addLine(to: CGPoint(x: x(crossing), y: y(maxHumidityRatio)))
                }
                break
            }
            let point = CGPoint(x: x(t), y: y(w))
            if started { path.addLine(to: point) } else { path.move(to: point); started = true }
            previous = (t, w)
            t += 0.25
        }
        return path
    }

    let saturation = curve(relativeHumidity: 1)

    // The region of real moist air: everything below the saturation curve, and the whole column to
    // the right of where it leaves the plot. Filling it is what turns the curve from a swoosh into
    // a boundary — above it is not air, it is fog, and the icon should say so.
    let region = CGMutablePath()
    region.addPath(saturation)
    region.addLine(to: CGPoint(x: size, y: size))
    region.addLine(to: CGPoint(x: size, y: 0))
    region.addLine(to: CGPoint(x: 0, y: 0))
    region.closeSubpath()

    context.saveGState()
    context.addPath(region)
    context.clip()
    if let gradient = CGGradient(colorsSpace: space,
                                 colors: [colour(0x1E6FA8, 0.85), colour(0x14476B, 0.55)] as CFArray,
                                 locations: [0, 1]) {
        context.drawLinearGradient(gradient,
                                   start: CGPoint(x: plot.maxX, y: plot.minY),
                                   end: CGPoint(x: plot.minX, y: plot.maxY),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
    context.restoreGState()

    // One constant-humidity curve inside the region, for depth. Three of them fanned out and read
    // as decoration; one reads as a chart.
    context.setLineCap(.round)
    context.setStrokeColor(faint)
    context.setLineWidth(size * 0.016)
    context.addPath(curve(relativeHumidity: 0.5))
    context.strokePath()

    // The saturation curve itself.
    context.setStrokeColor(breeze)
    context.setLineWidth(size * 0.052)
    context.addPath(saturation)
    context.strokePath()

    // One state point, at 24 °C / 50 % — the condition the whole trade designs to.
    let centre = CGPoint(x: x(24), y: y(humidityRatio(dryBulb: 24, relativeHumidity: 0.5)))
    let radius = size * 0.062
    context.setFillColor(deepWater)
    context.fillEllipse(in: CGRect(x: centre.x - radius * 1.34, y: centre.y - radius * 1.34,
                                   width: radius * 2.68, height: radius * 2.68))
    context.setFillColor(working)
    context.fillEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius,
                                   width: radius * 2, height: radius * 2))
}

// MARK: - Output

func writePNG(size: Int, to url: URL) {
    let side = CGFloat(size)
    guard let context = CGContext(data: nil, width: size, height: size,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        fatalError("could not make a \(size)×\(size) context")
    }
    context.interpolationQuality = .high
    context.setAllowsAntialiasing(true)
    drawIcon(size: side, context: context)

    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("could not encode \(url.lastPathComponent)") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(url.path)") }
    print("wrote \(url.lastPathComponent)")
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconSet = root.appendingPathComponent("AirCore/Assets.xcassets/AppIcon.appiconset")
try? FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)

// One 1024 for iOS and watchOS, and the mac idiom's full ladder — macOS still wants every size,
// and letting Xcode downsample a 1024 loses the curve at 16 points.
for size in [16, 32, 64, 128, 256, 512, 1024] {
    writePNG(size: size, to: iconSet.appendingPathComponent("icon-\(size).png"))
}
