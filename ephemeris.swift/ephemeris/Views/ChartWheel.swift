import SwiftUI
import EphemerisKit

/// Stage 4 — the chart wheel: zodiac ring, planet glyphs, colored aspect chords (Nebula theme).
struct ChartWheel: View {
    let positions: [BodyPosition]
    let aspects: [DetectedAspect]
    /// Cusps to overlay; nil when no place is set (the wheel then draws exactly as before).
    var houses: HouseCusps? = nil

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let R = s * 0.46          // outer ring
            let Rin = s * 0.33        // inner ring (zodiac band inner edge)
            let Rpl = s * 0.27        // planet ring

            let ring = GraphicsContext.Shading.color(NebulaPalette.ring)
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - R, y: c.y - R, width: 2 * R, height: 2 * R)),
                       with: ring, lineWidth: 1)
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - Rin, y: c.y - Rin, width: 2 * Rin, height: 2 * Rin)),
                       with: ring, lineWidth: 1)

            // 12 sign sectors + solid violet chips
            let chip = s * 0.058
            for i in 0..<12 {
                var spoke = Path()
                spoke.move(to: pt(c, Rin, Double(i) * 30))
                spoke.addLine(to: pt(c, R, Double(i) * 30))
                ctx.stroke(spoke, with: ring, lineWidth: 1)
                let gp = pt(c, (R + Rin) / 2, Double(i) * 30 + 15)
                let rect = CGRect(x: gp.x - chip / 2, y: gp.y - chip / 2, width: chip, height: chip)
                ctx.fill(Path(roundedRect: rect, cornerRadius: chip * 0.27), with: .color(NebulaPalette.sign))
                ctx.draw(Text(ZodiacSign(rawValue: i)!.glyph + "\u{FE0E}")
                    .font(.system(size: chip * 0.6)).foregroundStyle(NebulaPalette.signGlyph), at: gp)
            }

            // House cusps — thin spokes across the inner disc, numbered just inside the band.
            // Drawn under the chords so the aspect pattern still reads on top.
            if let houses {
                let faint = GraphicsContext.Shading.color(NebulaPalette.ring.opacity(0.55))
                for n in 1...12 {
                    let lon = houses.cusp(n)
                    var spoke = Path()
                    spoke.move(to: pt(c, Rpl * 0.30, lon))
                    spoke.addLine(to: pt(c, Rin, lon))
                    ctx.stroke(spoke, with: faint,
                               style: StrokeStyle(lineWidth: 0.75, dash: [s * 0.012, s * 0.010]))
                    // House number in the middle of the house, just inside the zodiac band.
                    let mid = lon + AstroMath.norm360(houses.cusp(n + 1) - lon) / 2
                    ctx.draw(Text(n, format: .number)
                        .font(.system(size: s * 0.026))
                        .foregroundStyle(NebulaPalette.textFaint), at: pt(c, Rin * 0.90, mid))
                }
            }

            // Aspect chords — neon double-stroke (halo + core)
            for a in aspects {
                guard let pa = positions.first(where: { $0.body == a.a }),
                      let pb = positions.first(where: { $0.body == a.b }) else { continue }
                var line = Path()
                line.move(to: pt(c, Rpl, pa.longitude))
                line.addLine(to: pt(c, Rpl, pb.longitude))
                ctx.stroke(line, with: .color(a.type.color.opacity(0.2)),
                           style: StrokeStyle(lineWidth: s * 0.013, lineCap: .round))
                ctx.stroke(line, with: .color(a.type.color),
                           style: StrokeStyle(lineWidth: s * 0.004, lineCap: .round))
            }

            // The four angles — heavier accent axes, drawn over the chords so they stay legible.
            if let houses {
                let a = houses.angles
                for (lon, label) in [(a.ascendant, "AC"), (a.midheaven, "MC")] {
                    var axis = Path()
                    axis.move(to: pt(c, Rpl * 0.30, lon))
                    axis.addLine(to: pt(c, Rin, lon))
                    ctx.stroke(axis, with: .color(NebulaPalette.accent.opacity(0.85)),
                               style: StrokeStyle(lineWidth: s * 0.005, lineCap: .round))
                    // Opposite end (DC / IC) — same axis, lighter.
                    var opposite = Path()
                    opposite.move(to: pt(c, Rpl * 0.30, lon + 180))
                    opposite.addLine(to: pt(c, Rin, lon + 180))
                    ctx.stroke(opposite, with: .color(NebulaPalette.accent.opacity(0.35)),
                               style: StrokeStyle(lineWidth: s * 0.003, lineCap: .round))
                    // Label sits in the empty lane between the planet ring and the zodiac band
                    // (the same lane as the house numbers), so it doesn't sit on top of a glyph.
                    ctx.draw(Text(label)
                        .font(.system(size: s * 0.030, weight: .bold))
                        .foregroundStyle(NebulaPalette.accent), at: pt(c, Rin * 0.96, lon))
                }
            }

            // Planet glyphs — glowing light symbols
            ctx.drawLayer { layer in
                layer.addFilter(.shadow(color: Color(rgbHex: 0xA078FF).opacity(0.9), radius: s * 0.012))
                for p in positions {
                    let g = pt(c, Rpl, p.longitude)
                    layer.draw(Text(p.body.glyph + "\u{FE0E}")
                        .font(.system(size: s * 0.045)).foregroundStyle(NebulaPalette.glyph), at: g)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .nebulaCard()
        // A `Canvas` publishes nothing at all, so the wheel was invisible both to VoiceOver and to
        // any test asking "did the Chart tab actually render?". `.accessibilityElement()` first —
        // an identifier on a bare container is a silent no-op on macOS (trap 5).
        .accessibilityElement()
        .accessibilityIdentifier("chart.wheel")
        .accessibilityLabel(Text(L.loc("Chart wheel")))
    }

    /// 0° Aries at left, counterclockwise. Shared with the watch via `ChartGeometry` — this was
    /// duplicated once and the copies silently disagreed about direction.
    private func pt(_ c: CGPoint, _ r: CGFloat, _ lon: Double) -> CGPoint {
        ChartGeometry.point(center: c, radius: r, longitude: lon)
    }
}
