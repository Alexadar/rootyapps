import SwiftUI
import EphemerisKit

/// Stage 4 — the chart wheel: zodiac ring, planet glyphs, colored aspect chords (Nebula theme).
struct ChartWheel: View {
    let positions: [BodyPosition]
    let aspects: [DetectedAspect]

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
    }

    /// 0° Aries at left, counterclockwise (matches the demo).
    private func pt(_ c: CGPoint, _ r: CGFloat, _ lon: Double) -> CGPoint {
        let ang = (180 - lon) * .pi / 180
        return CGPoint(x: c.x + r * cos(ang), y: c.y - r * sin(ang))
    }
}
