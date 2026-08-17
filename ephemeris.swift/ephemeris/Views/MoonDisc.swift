import SwiftUI

/// The Moon drawn as it actually appears in the sky at a given latitude.
///
/// ## The hemisphere rule, which is the whole reason this file exists
///
/// A waxing Moon is lit on the **right** as seen from the northern hemisphere and on the **left**
/// from the southern. Getting it backwards is the single most frequently reported defect in this
/// category of app, because half the planet sees it immediately and it looks like the app does not
/// know what the sky is doing.
///
/// `litOnRight` is a free function, not a private detail of the shape, precisely so it can be
/// tested without rendering anything. Its four cases are the whole rule.
///
/// The widget deliberately does **not** use this: it has no location, therefore no latitude, and a
/// disc drawn without one would be a guess. There it stays textual.
///
/// ## Terminator geometry
///
/// The terminator — the day/night boundary — is a half-**ellipse**, not a straight line and not an
/// offset circle. Its horizontal semi-axis is `|2k − 1|·r` for illuminated fraction `k`:
///
/// - `k = 0` (new) → semi-axis `r`, the ellipse coincides with the limb, nothing is lit
/// - `k = 0.5` (quarter) → semi-axis 0, a straight edge
/// - `k = 1` (full) → semi-axis `r` the other way, the whole disc is lit
///
/// Drawing it as a circle offset sideways is the common shortcut and is visibly wrong near the
/// quarters, where it produces a lens shape instead of a flat edge.
func litOnRight(waxing: Bool, latitude: Double) -> Bool {
    // Southern hemisphere mirrors it. At exactly the equator either is defensible; northern is
    // chosen so the answer is total rather than undefined.
    let southern = latitude < 0
    return waxing != southern
}

/// The lit portion of the lunar disc.
struct MoonDisc: Shape {
    /// 0…1.
    var illumination: Double
    var litOnRight: Bool

    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let k = min(max(illumination, 0), 1)

        // −1 at new, 0 at the quarters, +1 at full.
        let x = 2 * k - 1
        // Signed horizontal reach of the terminator, positive meaning "bulges right". At full this
        // is −r, which turns the terminator into the left limb and closes a complete circle; at new
        // it is +r, which lays it exactly over the right limb and encloses nothing.
        let w = -x * r

        var p = Path()
        // Outer limb: top → bottom down the right-hand side.
        p.move(to: CGPoint(x: c.x, y: c.y - r))
        p.addArc(center: c, radius: r,
                 startAngle: .degrees(-90), endAngle: .degrees(90),
                 clockwise: false)

        // Terminator: bottom → top as a half-ellipse. Two cubics, using the standard circle
        // constant scaled on the x axis only — which is what makes it an ellipse rather than an arc.
        let kappa = 0.5522847498307936
        p.addCurve(to: CGPoint(x: c.x + w, y: c.y),
                   control1: CGPoint(x: c.x + w * kappa, y: c.y + r),
                   control2: CGPoint(x: c.x + w, y: c.y + r * kappa))
        p.addCurve(to: CGPoint(x: c.x, y: c.y - r),
                   control1: CGPoint(x: c.x + w, y: c.y - r * kappa),
                   control2: CGPoint(x: c.x + w * kappa, y: c.y - r))
        p.closeSubpath()

        guard !litOnRight else { return p }
        // Mirror about the vertical centre line rather than deriving a second set of control
        // points. One geometry, one place for it to be wrong.
        return p.applying(CGAffineTransform(translationX: -c.x, y: 0)
                            .concatenating(CGAffineTransform(scaleX: -1, y: 1))
                            .concatenating(CGAffineTransform(translationX: c.x, y: 0)))
    }
}

/// The disc with its unlit remainder, sized for a calendar cell.
struct MoonDiscView: View {
    var illumination: Double
    var waxing: Bool
    var latitude: Double
    var size: CGFloat = 18

    var body: some View {
        ZStack {
            Circle()
                .fill(NebulaPalette.cardFill)
                .overlay(Circle().strokeBorder(NebulaPalette.ring, lineWidth: 0.5))
            MoonDisc(illumination: illumination,
                     litOnRight: litOnRight(waxing: waxing, latitude: latitude))
                .fill(NebulaPalette.glyph)
        }
        .frame(width: size, height: size)
        // The percentage is the accessible truth; the drawing is decoration over it. A blind user
        // gets the number, and a sighted one in Sydney gets the correct handedness.
        // Interpolating a String gives the key "%@ illuminated" — the same one the widget and the
        // calendar use. Interpolating the Int and writing a literal `%` would instead bake the
        // percent sign into the key as a malformed format specifier.
        .accessibilityLabel(Text("\(percentText) illuminated"))
    }

    private var percentText: String { "\(Int((illumination * 100).rounded()))%" }
}
