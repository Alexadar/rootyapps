import SwiftUI
import Charts

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
            let inset: CGFloat = 30
            let origin = CGPoint(x: inset + 6, y: size.height - inset)

            // scale so the longest vector fits the frame
            let maxMag = max(s.tas, s.groundSpeed, 1)
            let usable = min(size.width, size.height) - inset * 2
            let scale = usable / maxMag

            func vec(bearing: Double, mag: Double, from: CGPoint) -> CGPoint {
                let r = bearing * .pi / 180
                return CGPoint(x: from.x + CGFloat(sin(r)) * CGFloat(mag) * scale,
                               y: from.y - CGFloat(cos(r)) * CGFloat(mag) * scale)
            }

            // compass ring
            let ring = Path(ellipseIn: CGRect(x: origin.x - usable, y: origin.y - usable,
                                              width: usable * 2, height: usable * 2))
            ctx.stroke(ring, with: .color(tc.hairline), lineWidth: 1)

            let air   = vec(bearing: s.trueHeading, mag: s.tas, from: origin)         // heading / TAS
            let track = vec(bearing: s.trueCourse,  mag: s.groundSpeed, from: origin) // ground / GS
            // wind vector completes the triangle: air -> track

            arrow(ctx, origin, track, tc.accent(.nav),  width: 3.5)   // TRACK / GS
            arrow(ctx, origin, air,   tc.accent(.wind), width: 3.5)   // HDG / TAS
            arrow(ctx, air,    track, tc.accent(.fuel), width: 3.5)   // WIND

            // aircraft glyph at origin, rotated to heading
            var glyph = ctx
            glyph.translateBy(x: origin.x, y: origin.y)
            glyph.rotate(by: .degrees(s.trueHeading))
            glyph.fill(aircraftPath(), with: .color(tc.textPrimary))
        }
        .accessibilityElement()
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

    private var accent: Color { tc.accent(.weightBal) }
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
        .accessibilityLabel(
            "Weight and balance. Loaded \(Int(takeoff.weight)) pounds at CG "
            + "\(takeoff.arm, specifier: "%.1f") inches, "
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
