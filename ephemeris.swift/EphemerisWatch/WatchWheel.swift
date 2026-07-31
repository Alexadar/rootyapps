import SwiftUI
import EphemerisKit

/// The chart wheel at watch size — everything the phone shows, redesigned rather than dropped.
///
/// The first pass simply deleted the layers that broke: aspect chords, cusps, house numbers, sign
/// chips, glow. That answers "does a stripped wheel fit" but concedes the interesting question.
/// Each layer is back, re-drawn so it costs less ink at 41mm:
///
///   sign chips   -> alternating sector shading. A solid chip is nearly as wide as its own 30°
///                   sector here, which turns the ring into a band and kills glyph contrast.
///                   Alternating light/dark sectors give the same "these are cells" reading for
///                   almost no ink, and it scales to any size.
///   house cusps  -> ticks on the inner edge instead of full radial spokes. Twelve more spokes
///                   are indistinguishable from the twelve sign spokes already there; ticks are
///                   distinguishable by *length*, which survives shrinking.
///   house numbers-> angular houses only (1/4/7/10). Twelve numerals in a ~10pt lane land at
///                   about 4pt, which is not small but unreadable. The four that carry meaning
///                   are legible and the rest are inferable by counting.
///   AC/MC        -> drawn as full diameters, so DC and IC come free with no extra strokes. The
///                   phone draws them as two separate half-axes.
///   aspects      -> tightest only. Up to ~45 double-stroked neon chords become a grey mass and
///                   sit on top of the glyphs. Filtering to near-exact aspects keeps the pattern
///                   that matters and leaves the disc readable.
///   glow         -> a single soft pass, not the phone's halo+core. At 12pt a heavy halo reads
///                   as a smudge; a light one still lifts the glyph off the disc.
struct WatchWheel: View {
    let positions: [BodyPosition]
    let aspects: [DetectedAspect]
    let houses: HouseCusps?
    /// Only aspects at least this exact are drawn. The 41mm probe showed clear headroom at
    /// 2°, so this is opened up; it stays a parameter because it is the first thing to
    /// pull back if a denser chart turns the disc into a mass.
    var maxOrb: Double = 6.0

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let rOuter = s * 0.48
            let rInner = s * 0.37
            let rGlyph = s * 0.27
            // 0° Aries at the left, matching the phone — NOT anchored to the Ascendant.
            // Anchoring to the AC looks right on a static chart and is unusable while scrubbing:
            // the Ascendant sweeps a full 360° per day, so every Crown detent spun the whole
            // zodiac ring. With a fixed zodiac the planets drift slowly and the AC/MC axis
            // rotates instead, which is what the eye can actually follow.
            let rot = 0.0

            // ── sector shading (replaces solid chips) ──
            for i in 0..<12 where i % 2 == 0 {
                let a0 = Double(i) * 30
                ctx.fill(sector(c, rInner, rOuter, a0, a0 + 30, rot),
                         with: .color(.white.opacity(0.07)))
            }

            ctx.stroke(circle(c, rOuter), with: .color(.white.opacity(0.28)), lineWidth: 0.8)
            ctx.stroke(circle(c, rInner), with: .color(.white.opacity(0.28)), lineWidth: 0.8)

            for i in 0..<12 {
                let a = Double(i) * 30
                ctx.stroke(Path { p in
                    p.move(to: pt(c, rInner, a, rot)); p.addLine(to: pt(c, rOuter, a, rot))
                }, with: .color(.white.opacity(0.20)), lineWidth: 0.5)
                ctx.draw(Text(verbatim: (ZodiacSign(rawValue: i) ?? .aries).glyph + "\u{FE0E}")
                            .font(.system(size: s * 0.070))
                            .foregroundStyle(.white.opacity(0.9)),
                         at: pt(c, (rInner + rOuter) / 2, a + 15, rot))
            }

            // ── house cusps as inner-edge ticks ──
            if let houses {
                for n in 1...12 {
                    let lon = houses.cusp(n)
                    let angular = (n == 1 || n == 4 || n == 7 || n == 10)
                    let len = angular ? s * 0.055 : s * 0.032
                    ctx.stroke(Path { p in
                        p.move(to: pt(c, rInner, lon, rot))
                        p.addLine(to: pt(c, rInner - len, lon, rot))
                    }, with: .color(.white.opacity(angular ? 0.55 : 0.30)),
                       lineWidth: angular ? 0.9 : 0.6)

                    if angular {
                        let mid = lon + AstroMath.norm360(houses.cusp(n % 12 + 1) - lon) / 2
                        ctx.draw(Text(verbatim: "\(n)")
                                    .font(.system(size: s * 0.045))
                                    .foregroundStyle(.white.opacity(0.45)),
                                 at: pt(c, rInner - s * 0.085, mid, rot))
                    }
                }
            }

            // ── aspects: tightest only, single stroke ──
            // DetectedAspect carries the two bodies, not their positions, so resolve longitudes
            // from the position list rather than assuming an ordering.
            var lonOf: [CelestialBody: Double] = [:]
            for p in positions { lonOf[p.body] = p.longitude }
            for a in aspects where a.orb <= maxOrb {
                guard let la = lonOf[a.a], let lb = lonOf[a.b] else { continue }
                ctx.stroke(Path { p in
                    p.move(to: pt(c, rGlyph * 0.86, la, rot))
                    p.addLine(to: pt(c, rGlyph * 0.86, lb, rot))
                }, with: .color(a.type.color.opacity(0.75)), lineWidth: 0.7)
            }

            // ── angles as full diameters: AC/DC and MC/IC in two strokes ──
            if let houses {
                for (lon, label) in [(houses.angles.ascendant, "AC"), (houses.angles.midheaven, "MC")] {
                    ctx.stroke(Path { p in
                        p.move(to: pt(c, rOuter, lon, rot))
                        p.addLine(to: pt(c, rOuter, lon + 180, rot))
                    }, with: .color(.pink.opacity(0.65)), lineWidth: 0.8)
                    ctx.draw(Text(verbatim: label).font(.system(size: s * 0.052))
                                .foregroundStyle(.pink),
                             at: pt(c, rInner - s * 0.02, lon, rot))
                }
            }

            // ── planets, one soft glow pass, conjunctions fanned out ──
            ctx.drawLayer { layer in
                layer.addFilter(.shadow(color: .white.opacity(0.5), radius: s * 0.012))
                for (p, drawLon) in Self.spread(positions, minSeparation: 9) {
                    layer.draw(Text(verbatim: p.body.glyph + "\u{FE0E}")
                                .font(.system(size: s * 0.082))
                                .foregroundStyle(p.retrograde ? .orange : .white),
                               at: pt(c, rGlyph, drawLon, rot))
                    // Leader line back to the true longitude, so a fanned glyph still reads as
                    // belonging where it actually is rather than where it was moved to.
                    if abs(AstroMath.norm360(drawLon - p.longitude + 180) - 180) > 0.5 {
                        layer.stroke(Path { path in
                            path.move(to: pt(c, rGlyph * 1.14, p.longitude, rot))
                            path.addLine(to: pt(c, rGlyph * 1.05, drawLon, rot))
                        }, with: .color(.white.opacity(0.35)), lineWidth: 0.5)
                    }
                }
            }
        }
        // The Canvas publishes nothing on its own, so without this the crown tests have no element
        // to wait on before starting to scrub. `.accessibilityElement()` before the identifier —
        // a bare container is a silent no-op on macOS and unreliable here too (trap 5).
        .accessibilityElement()
        .accessibilityIdentifier("watch.wheel")
    }

    /// Nudges glyphs apart until neighbours are at least `minSeparation` degrees away.
    ///
    /// Purely a *drawing* offset — the aspect chords and everything else still use the true
    /// longitude. Sorting first, then walking once, keeps the order around the wheel intact so a
    /// cluster fans in the direction it is already going rather than scattering.
    static func spread(_ positions: [BodyPosition],
                       minSeparation: Double) -> [(BodyPosition, Double)] {
        let sorted = positions.sorted { AstroMath.norm360($0.longitude) < AstroMath.norm360($1.longitude) }
        var out: [(BodyPosition, Double)] = []
        var previous: Double?
        for p in sorted {
            var lon = AstroMath.norm360(p.longitude)
            if let previous, lon - previous < minSeparation { lon = previous + minSeparation }
            previous = lon
            out.append((p, lon))
        }
        return out
    }

    private func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }

    private func sector(_ c: CGPoint, _ r0: CGFloat, _ r1: CGFloat,
                        _ a0: Double, _ a1: Double, _ rot: Double) -> Path {
        var p = Path()
        p.move(to: pt(c, r0, a0, rot))
        p.addLine(to: pt(c, r1, a0, rot))
        for d in stride(from: a0, through: a1, by: 3) { p.addLine(to: pt(c, r1, d, rot)) }
        p.addLine(to: pt(c, r0, a1, rot))
        for d in stride(from: a1, through: a0, by: -3) { p.addLine(to: pt(c, r0, d, rot)) }
        p.closeSubpath()
        return p
    }

    /// Delegates to `ChartGeometry` so the watch and the phone cannot disagree. The hand-rolled
    /// version this replaces used `lon + 180`, which drew the whole zodiac backwards.
    private func pt(_ c: CGPoint, _ r: CGFloat, _ lon: Double, _ rot: Double) -> CGPoint {
        ChartGeometry.point(center: c, radius: r, longitude: lon - rot)
    }
}
