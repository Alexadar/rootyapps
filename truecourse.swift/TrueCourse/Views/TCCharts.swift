import SwiftUI
import Charts
import WindKit

// TrueCourse — the two signature visualizations. Both are pure SwiftUI / Swift Charts:
// no bitmaps, Dynamic-Type & VoiceOver friendly, and they recolour with the theme.

// MARK: - 1. Wind triangle

/// The solved wind triangle. All angles are magnetic/true degrees (0…360, 0 = North).
struct WindSolution {
    var trueCourse: Double     // desired track over the ground
    var trueHeading: Double    // where the nose points (course ± WCA)
    var tas: Double            // true airspeed, kt
    var groundSpeed: Double    // kt
    var windFrom: Double       // wind direction (FROM), degrees
    var windSpeed: Double      // kt
    var wca: Double            // wind-correction angle, signed (+ = right)
}

/// Heading / track / wind vectors drawn as an honest vector triangle over a compass ring.
/// air (TAS) + wind = ground (track). Recolours with `\.tc`; scales to fit its frame.
struct WindTriangleView: View {
    @Environment(\.tc) private var tc
    let solution: WindSolution

    var body: some View {
        Canvas { ctx, size in
            let s = solution
            let inset: CGFloat = 26
            // Centred origin so the whole compass rose is visible (not a corner quadrant).
            let origin = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - inset

            // scale so the longest vector reaches the ring
            let maxMag = max(s.tas, s.groundSpeed, 1)
            let scale = radius / maxMag

            // full compass ring + cardinal ticks
            let ring = Path(ellipseIn: CGRect(x: origin.x - radius, y: origin.y - radius,
                                              width: radius * 2, height: radius * 2))
            ctx.stroke(ring, with: .color(tc.hairline), lineWidth: 1)
            for deg in stride(from: 0, to: 360, by: 30) {
                let r = Double(deg) * .pi / 180
                let outer = radius, inner = radius - (deg % 90 == 0 ? 9 : 5)
                var tick = Path()
                tick.move(to: CGPoint(x: origin.x + CGFloat(sin(r)) * inner,
                                      y: origin.y - CGFloat(cos(r)) * inner))
                tick.addLine(to: CGPoint(x: origin.x + CGFloat(sin(r)) * outer,
                                         y: origin.y - CGFloat(cos(r)) * outer))
                ctx.stroke(tick, with: .color(tc.hairline), lineWidth: 1)
            }

            // Geometry from WindKit (unit-tested: recovers heading/TAS, course/GS, wind, and closes).
            let tri = Wind.triangle(courseDeg: s.trueCourse, tasKt: s.tas,
                                    headingDeg: s.trueHeading, gsKt: s.groundSpeed)
            func pt(_ v: Wind.Vec2) -> CGPoint {
                CGPoint(x: origin.x + CGFloat(v.x) * scale, y: origin.y + CGFloat(v.y) * scale)
            }
            let air = pt(tri.air)      // heading / TAS
            let track = pt(tri.track)  // ground / GS ; wind vector completes it: air -> track

            // Three distinct vectors — coloured by semantic token, not group accent, so each
            // leg of the triangle stays legible on its own (and survives Night's red-shift).
            arrow(ctx, origin, track, tc.brand,   width: 3.5)   // TRACK / GS
            arrow(ctx, origin, air,   tc.normal,  width: 3.5)   // HDG / TAS
            arrow(ctx, air,    track, tc.caution, width: 3.5)   // WIND

            // aircraft glyph at origin, rotated to heading
            var glyph = ctx
            glyph.translateBy(x: origin.x, y: origin.y)
            glyph.rotate(by: .degrees(s.trueHeading))
            glyph.fill(aircraftPath(), with: .color(tc.textPrimary))
        }
        .accessibilityElement()
        .accessibilityIdentifier("chart.windTriangle")
        .accessibilityLabel(
            "Wind triangle. Heading \(Int(solution.trueHeading)) degrees, "
            + "ground speed \(Int(solution.groundSpeed)) knots, "
            + "wind correction \(abs(Int(solution.wca)) ) degrees "
            + (solution.wca < 0 ? "left." : "right."))
    }

    private func arrow(_ ctx: GraphicsContext, _ a: CGPoint, _ b: CGPoint,
                       _ color: Color, width: CGFloat) {
        var line = Path(); line.move(to: a); line.addLine(to: b)
        ctx.stroke(line, with: .color(color), lineWidth: width)
        // arrowhead
        let ang = atan2(b.y - a.y, b.x - a.x)
        let h: CGFloat = 11
        var head = Path()
        head.move(to: b)
        head.addLine(to: CGPoint(x: b.x - h * cos(ang - .pi/7), y: b.y - h * sin(ang - .pi/7)))
        head.addLine(to: CGPoint(x: b.x - h * cos(ang + .pi/7), y: b.y - h * sin(ang + .pi/7)))
        head.closeSubpath()
        ctx.fill(head, with: .color(color))
    }

    private func aircraftPath() -> Path {
        var p = Path()
        let pts: [CGPoint] = [(0,-13),(3,4),(11,9),(3,7),(3,14),(7,17),(0,15),
                              (-7,17),(-3,14),(-3,7),(-11,9),(-3,4)].map { CGPoint(x: $0.0, y: $0.1) }
        p.addLines(pts); p.closeSubpath(); return p
    }
}

// MARK: - 2. Weight & Balance — CG envelope

struct CGPointSample: Identifiable {
    let id = UUID()
    let label: String
    let arm: Double      // inches aft of datum
    let weight: Double   // lb
}

/// Category envelopes as (arm, weight) polygons. Feed the aircraft's real limits.
struct CGEnvelope {
    let name: String
    let vertices: [(arm: Double, weight: Double)]   // ordered, closed automatically
}

/// CG-envelope chart: the loaded point (and its takeoff→landing travel as fuel burns)
/// plotted against the category envelope. Green when inside, red when out.
/// Axes/ticks/points come from Swift Charts; the filled envelope polygons are drawn in a
/// `chartOverlay` mapped through the chart's coordinate proxy.
struct CGEnvelopeChart: View {
    @Environment(\.tc) private var tc
    let envelopes: [CGEnvelope]          // e.g. [normal, utility]
    let takeoff: CGPointSample
    let landing: CGPointSample?
    let armDomain: ClosedRange<Double>
    let weightDomain: ClosedRange<Double>

    var isWithin: Bool                    // supplied by the W&B ViewModel

    private var accent: Color { tc.accent(.performance) }
    private var pointColor: Color { isWithin ? tc.normal : tc.warning }

    var body: some View {
        Chart {
            // travel line: takeoff -> landing
            if let landing {
                LineMark(x: .value("Arm", takeoff.arm),   y: .value("Weight", takeoff.weight),
                         series: .value("s", "travel"))
                LineMark(x: .value("Arm", landing.arm),   y: .value("Weight", landing.weight),
                         series: .value("s", "travel"))
                    .lineStyle(StrokeStyle(lineWidth: 1.6, dash: [4, 3]))
                    .foregroundStyle(tc.normal)
                PointMark(x: .value("Arm", landing.arm), y: .value("Weight", landing.weight))
                    .symbolSize(60).symbol(.circle).foregroundStyle(tc.normal.opacity(0.5))
            }
            // loaded takeoff point (hero)
            PointMark(x: .value("Arm", takeoff.arm), y: .value("Weight", takeoff.weight))
                .symbolSize(150)
                .foregroundStyle(pointColor)
                .annotation(position: .top, spacing: 6) {
                    Text("\(takeoff.label) · \(Int(takeoff.weight)) lb")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(pointColor)
                }
        }
        .chartXScale(domain: armDomain)
        .chartYScale(domain: weightDomain)
        .chartXAxisLabel("CG ARM — in aft of datum")
        .chartYAxisLabel("WEIGHT — lb")
        .chartPlotStyle { $0.background(tc.grouped) }
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let plot = proxy.plotFrame.map({ geo[$0] }) {
                    ForEach(Array(envelopes.enumerated()), id: \.offset) { idx, env in
                        let path = envelopePath(env, proxy: proxy, plot: plot)
                        // first envelope = filled normal category; others = dashed outline
                        if idx == 0 {
                            path.fill(accent.opacity(0.12))
                            path.stroke(accent, lineWidth: 2)
                        } else {
                            path.stroke(tc.textTertiary,
                                        style: StrokeStyle(lineWidth: 1.6, dash: [5, 4]))
                        }
                    }
                }
            }
        }
        .frame(minHeight: 260)
        .accessibilityElement()
        .accessibilityIdentifier("chart.cgEnvelope")
        .accessibilityLabel(
            "Weight and balance. Loaded \(Int(takeoff.weight)) pounds at CG "
            + String(format: "%.1f", takeoff.arm) + " inches, "
            + (isWithin ? "within limits." : "outside the envelope."))
    }

    private func envelopePath(_ env: CGEnvelope,
                              proxy: ChartProxy, plot: CGRect) -> Path {
        var p = Path()
        for (i, v) in env.vertices.enumerated() {
            guard let x = proxy.position(forX: v.arm),
                  let y = proxy.position(forY: v.weight) else { continue }
            let pt = CGPoint(x: x + plot.minX, y: y + plot.minY)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}
