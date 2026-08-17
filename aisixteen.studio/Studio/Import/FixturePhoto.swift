// ⚠️ DEBUG only. The whole file compiles out of Release, so the fixture door does not merely go
// unused in a shipped build — it does not exist in one.
#if DEBUG
import Foundation
import CoreGraphics

/// A photo the app can import without a picker, for UI tests only.
///
/// `PhotosPicker` runs out of process, which is exactly what makes it private — and exactly what
/// makes it undrivable from XCUITest without granting the runner library access and depending on
/// whatever pictures happen to be on the simulator. So the tests bring their own photo through this
/// door instead.
///
/// ⚠️ **DEBUG only, behind `LaunchOverride`.** The whole mechanism compiles out of Release, so there
/// is no path to it in a shipped build.
enum FixturePhoto {

    static let launchKey = "STUDIO_FIXTURE_PHOTO"

    static var isRequested: Bool { LaunchOverride.flag(launchKey) }

    /// A synthetic photograph: a sky gradient, a horizon and a bright disc. Not flat — an unsharp
    /// mask over a flat field changes nothing, and a test that compared two identical pictures would
    /// pass while proving the opposite of what it claims.
    static func make(width: Int = 1200, height: Int = 900) -> CGImage? {
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        let sky = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                             colors: [CGColor(red: 0.15, green: 0.29, blue: 0.44, alpha: 1),
                                      CGColor(red: 0.62, green: 0.72, blue: 0.80, alpha: 1),
                                      CGColor(red: 0.86, green: 0.80, blue: 0.68, alpha: 1)] as CFArray,
                             locations: [0, 0.6, 1])!
        context.drawLinearGradient(sky,
                                   start: CGPoint(x: 0, y: height),
                                   end: CGPoint(x: 0, y: Double(height) * 0.35),
                                   options: [])

        context.setFillColor(CGColor(red: 0.96, green: 0.85, blue: 0.60, alpha: 1))
        context.fillEllipse(in: CGRect(x: Double(width) * 0.66, y: Double(height) * 0.52,
                                       width: 150, height: 150))

        context.setFillColor(CGColor(red: 0.16, green: 0.23, blue: 0.28, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: Double(width), height: Double(height) * 0.34))

        // A little high-frequency detail, so sharpening has something to bite on.
        context.setFillColor(CGColor(red: 0.30, green: 0.38, blue: 0.42, alpha: 1))
        for index in 0..<60 {
            let x = Double(index) * Double(width) / 60
            context.fill(CGRect(x: x, y: Double(height) * 0.30,
                                width: 6, height: Double(4 + (index % 7) * 5)))
        }

        return context.makeImage()
    }

    static func data() -> Data? {
        make().flatMap { ImageCoder.encode($0, as: .png) }
    }
}

#endif
