import SwiftUI

/// Moon phase drawn as a real terminator at the true illuminated fraction.
///
/// **Never use an emoji for this.** 🌑/🌕 quantise to eight phases, so 18.0% and
/// 31.4% render identically; they also arrive in someone else's colour and drawing
/// style, which breaks a monochrome glyph vocabulary. This holds down to 15 pt and
/// is used on Now, on Events, and in every complication family.
struct MoonPhaseDisc: View {
    /// 0 = new, 0.5 = quarter, 1 = full.
    let illuminated: Double
    /// True while waxing — lit limb on the right.
    var waxing: Bool = true
    var diameter: CGFloat = 22

    var body: some View {
        Canvas { ctx, size in
            let R = min(size.width, size.height) / 2
            let c = CGPoint(x: size.width / 2, y: size.height / 2)

            ctx.fill(Path(ellipseIn: CGRect(x: c.x - R, y: c.y - R, width: R * 2, height: R * 2)),
                     with: .color(NebulaPalette.bgTop))
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - R, y: c.y - R, width: R * 2, height: R * 2)),
                       with: .color(NebulaPalette.cardBorder), lineWidth: 0.8)

            var p = Path()
            let f = max(0, min(1, illuminated))
            let rx = abs(R * (1 - 2 * f))

            // Outer limb: half circle on the lit side.
            p.move(to: CGPoint(x: c.x, y: c.y - R))
            p.addArc(center: c, radius: R,
                     startAngle: .degrees(-90),
                     endAngle: .degrees(90),
                     clockwise: !waxing)
            // Terminator: an ellipse arc whose width is the phase, concave before
            // quarter and convex after.
            p.addArc(center: c, radius: R,
                     startAngle: .degrees(90), endAngle: .degrees(-90),
                     clockwise: waxing)
            p.closeSubpath()

            // Scale the terminator half horizontally to rx. Drawn as a clip so the
            // shape stays exact at any size.
            ctx.clip(to: Path(ellipseIn: CGRect(x: c.x - R, y: c.y - R, width: R * 2, height: R * 2)))
            ctx.fill(terminatorPath(c: c, R: R, rx: rx, f: f), with: .color(NebulaPalette.glyph))
        }
        .frame(width: diameter, height: diameter)
        .accessibilityLabel(Text(phaseName))
        .accessibilityValue(Text(illuminated.formatted(.percent.precision(.fractionLength(1)))))
    }

    private func terminatorPath(c: CGPoint, R: CGFloat, rx: CGFloat, f: Double) -> Path {
        var p = Path()
        let sign: CGFloat = waxing ? 1 : -1
        p.move(to: CGPoint(x: c.x, y: c.y - R))
        // Lit limb.
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + R),
                       control: CGPoint(x: c.x + sign * R * 1.34, y: c.y))
        // Terminator, bulging back through rx.
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - R),
                       control: CGPoint(x: c.x + sign * rx * (f < 0.5 ? -1.34 : 1.34), y: c.y))
        p.closeSubpath()
        return p
    }

    private var phaseName: String {
        switch illuminated {
        case ..<0.02: return String(localized: "New Moon")
        case ..<0.48: return String(localized: waxing ? "Waxing crescent" : "Waning crescent")
        case ..<0.52: return String(localized: waxing ? "First quarter" : "Last quarter")
        case ..<0.98: return String(localized: waxing ? "Waxing gibbous" : "Waning gibbous")
        default:      return String(localized: "Full Moon")
        }
    }
}

private extension String {
    /// Locale must resolve from the App Group, not the system — see NebulaComplications.
    init(localized key: String) { self = NSLocalizedString(key, comment: "") }
}
