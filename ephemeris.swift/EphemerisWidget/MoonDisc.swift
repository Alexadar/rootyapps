import SwiftUI

/// The lit region of the Moon, as a `Shape`.
///
/// Four hand-rolled attempts inside a `Canvas` failed before this — two circular arcs (fills to a
/// solid disc, because the terminator is an *ellipse*), a transformed unit arc (built at the wrong
/// origin, drew off-canvas), clip-and-paint (a translucent "shadow" over white darkens nothing),
/// and booleans over a half-**rectangle** (collapsed to a full disc). The construction that works
/// is the documented one: a half-**circle** combined with an ellipse whose width is
/// `cos(phase) · r · 2`, choosing subtract or union by the sign of that cosine.
///
///   phase 0     new        cos = +1   half − full-width ellipse  → nothing lit
///   phase 90°   first qtr  cos =  0   ellipse collapses to a line → exact half
///   phase 180°  full       cos = −1   half ∪ full-width ellipse  → whole disc
///
/// Being a `Shape` rather than Canvas drawing is what makes it usable as a mask, so the lit part
/// can be an actual moon surface instead of a flat fill.
struct MoonShape: Shape {
    /// Sun–Moon elongation: 0° new, 180° full. Waxing is 0–180°, waning 180–360°.
    var elongation: Double

    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let radians = elongation * .pi / 180
        let cosine = cos(radians)
        let waxing = sin(radians) >= 0

        // Lit limb: the semicircle on the illuminated side.
        var half = Path()
        half.addRelativeArc(center: c, radius: r,
                            startAngle: .degrees(waxing ? -90 : 90),
                            delta: .degrees(180))
        half.closeSubpath()

        // Terminator: an ellipse spanning the full height, its width the foreshortened diameter.
        let w = abs(cosine) * r
        var ellipse = Path()
        ellipse.addEllipse(in: CGRect(x: c.x - w, y: c.y - r, width: w * 2, height: r * 2))

        // Near new/full the ellipse is the whole width; cutting versus adding is what separates a
        // crescent from a gibbous.
        return cosine > 0 ? half.subtracting(ellipse) : half.union(ellipse)
    }
}

/// A moon: lit surface, shaded limb.
///
/// The lit part is a real surface — a radial gradient with a faint terminator falloff — masked to
/// `MoonShape`, rather than a flat white fill. The unlit part stays visible as a dark limb so the
/// body reads as a sphere in shadow instead of a bite taken out of nothing, which matters on a
/// complication where the background is transparent.
struct MoonDisc: View {
    /// Sun–Moon elongation in degrees: 0 new, 180 full.
    var elongation: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.14))
                .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 0.6))

            Circle()
                .fill(
                    RadialGradient(colors: [.white, Color(white: 0.82)],
                                   center: .init(x: 0.38, y: 0.34),
                                   startRadius: 0, endRadius: 22)
                )
                .mask(MoonShape(elongation: elongation))
        }
    }
}

#Preview {
    HStack(spacing: 6) {
        ForEach([10.0, 60, 90, 140, 180, 220, 270, 330], id: \.self) {
            MoonDisc(elongation: $0).frame(width: 30, height: 30)
        }
    }
    .padding()
    .background(.black)
}
