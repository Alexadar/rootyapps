import SwiftUI
import EphemerisKit

/// Stage 4 — the chart wheel: zodiac ring, planet glyphs, colored aspect chords.
struct ChartWheel: View {
    let positions: [BodyPosition]
    let aspects: [DetectedAspect]

    var body: some View {
        GlassEffectContainer {
            Canvas { ctx, size in
                let s = min(size.width, size.height)
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let R = s * 0.46          // outer ring
                let Rin = s * 0.30        // inner ring (zodiac band edge)
                let Rpl = s * 0.37        // planet ring

                let ring = GraphicsContext.Shading.color(.secondary.opacity(0.5))
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - R, y: c.y - R, width: 2 * R, height: 2 * R)),
                           with: ring, lineWidth: 1)
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - Rin, y: c.y - Rin, width: 2 * Rin, height: 2 * Rin)),
                           with: ring, lineWidth: 1)

                // 12 sign sectors + glyphs
                for i in 0..<12 {
                    var spoke = Path()
                    spoke.move(to: pt(c, Rin, Double(i) * 30))
                    spoke.addLine(to: pt(c, R, Double(i) * 30))
                    ctx.stroke(spoke, with: ring, lineWidth: 1)
                    let gp = pt(c, (R + Rin) / 2, Double(i) * 30 + 15)
                    ctx.draw(Text(ZodiacSign(rawValue: i)!.glyph)
                        .font(.system(size: s * 0.04)).foregroundStyle(.secondary), at: gp)
                }

                // Aspect chords
                for a in aspects {
                    guard let pa = positions.first(where: { $0.body == a.a }),
                          let pb = positions.first(where: { $0.body == a.b }) else { continue }
                    var line = Path()
                    line.move(to: pt(c, Rin, pa.longitude))
                    line.addLine(to: pt(c, Rin, pb.longitude))
                    ctx.stroke(line, with: .color(a.type.color.opacity(0.8)), lineWidth: 1.5)
                }

                // Planet glyphs
                for p in positions {
                    let g = pt(c, Rpl, p.longitude)
                    ctx.draw(Text(p.body.glyph)
                        .font(.system(size: s * 0.045)).foregroundStyle(.primary), at: g)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .padding(16)
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
        }
    }

    /// 0° Aries at left, counterclockwise (matches the demo).
    private func pt(_ c: CGPoint, _ r: CGFloat, _ lon: Double) -> CGPoint {
        let ang = (180 - lon) * .pi / 180
        return CGPoint(x: c.x + r * cos(ang), y: c.y - r * sin(ang))
    }
}
