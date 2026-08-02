import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// Marine Nav — chart treatment.
//
// PRESENTATION ONLY. These views receive already-computed samples and events and
// map them to points. No prediction, no interpolation of physical quantities, no
// unit conversion: the caller hands over what TidesKit produced.
//
// What the structural build lacked and this adds: gridlines, an hour axis in
// station-local time, a LABELLED datum line, extremes annotated in place, a now
// marker, and a drag readout.
//
// ── One thing the design needs and the Kits do not expose ────────────────────
// The day/night (civil twilight) bands want sunrise/sunset for the station and
// day. CelestialNavKit exposes GHA/Dec and altitude corrections, but no rise/set
// solver, and TidesKit has none. So `twilight:` is an OPTIONAL input: pass nil
// and the bands are simply not drawn. It is not computed here — adding a
// rise/set API to CelestialNavKit (oracle: Nautical Almanac rise/set tables) is
// the honest way to light this up.
// ─────────────────────────────────────────────────────────────────────────────

/// A time span within the 24 h window, expressed as fractions 0…1 of the window.
struct ChartShading {
    let start: Double
    let end: Double
}

/// One annotated point on a chart: an extreme, a slack, a maximum.
struct ChartMarker: Identifiable {
    let id: Int
    /// 0…1 across the window.
    let x: Double
    /// The already-formatted value, e.g. "4.58".
    let value: String
    /// The already-formatted station-local time, e.g. "11:58".
    let time: String
    /// True for high water / flood; false for low water / ebb.
    let positive: Bool
    /// Slack water: drawn hollow, no value.
    var hollow: Bool = false
    /// The Kit's own value for this event, in the chart's units, used to place the
    /// dot vertically. Resolving y from the nearest 15-minute sample instead drew a
    /// high water up to 7.5 min off-peak — visibly below the crest of its own curve.
    let y: Double
}

// MARK: - Axis

private struct HourAxis: View {
    @Environment(\.marine) private var theme
    /// Labels every 3 h, 00 … 24.
    let labels: [String]

    /// Labels are positioned at their true fraction of the width, so each one sits
    /// on its own gridline. An `HStack` of `.frame(maxWidth: .infinity)` cells put
    /// label *i* at (i+0.5)/n instead — every label missed its line, by a different
    /// amount. The two endpoints are nudged inward by half a label so 00 and 24 do
    /// not clip at the frame edges.
    var body: some View {
        GeometryReader { geo in
            ForEach(Array(labels.enumerated()), id: \.offset) { i, label in
                let f = Double(i) / Double(max(labels.count - 1, 1))
                Text(label)
                    .font(MarineType.mono10)
                    .foregroundStyle(theme.palette.inkDim)
                    .position(x: geo.size.width * f, y: geo.size.height / 2)
                    .offset(x: i == 0 ? 9 : (i == labels.count - 1 ? -9 : 0))
            }
        }
        .frame(height: 13)
        .padding(.top, 5)
        .padding(.bottom, 8)
        .overlay(alignment: .top) { theme.palette.hairline.frame(height: 1) }
    }
}

/// Keeps a marker's label inside the plot. The label sits above a high and below a
/// low, but a crest near the top edge (or a trough near the axis) left it clipped or
/// overlapping the hour labels — so when there is no room on the preferred side it
/// flips, and it is clamped either way. Shared by both charts.
private func labelPosition(_ my: CGFloat, positive: Bool, in size: CGSize,
                           offset: CGFloat, topInset: CGFloat) -> CGFloat {
    let margin: CGFloat = 15                 // half a two-line label
    var y = my + (positive ? -offset : offset)
    if y - margin < topInset { y = my + offset }
    if y + margin > size.height { y = my - offset }
    return min(max(y, topInset + margin), size.height - margin)
}

// MARK: - Tide curve

/// The hero visual: a day of predicted height, read as an instrument.
struct TideCurve: View {
    @Environment(\.marine) private var theme

    /// Heights, already computed by `Harmonics.heights`, in station units.
    let samples: [Double]
    /// Extremes from `Harmonics.extremes`, pre-formatted by the view model.
    let markers: [ChartMarker]
    /// Where "now" sits in the window, 0…1, or nil when the window is not today.
    let nowX: Double?
    /// Pre-formatted "now" readout, e.g. "09:41 · 3.56 ft".
    let nowLabel: String?
    /// Height of the chart datum (0.0) inside the plotted range — supplied so the
    /// datum line is drawn at the real zero, not at the bottom of the box.
    let datumValue: Double
    let datumLabel: String
    let unitLabel: String
    /// Optional civil-twilight bands. See the note at the top of this file.
    var twilight: [ChartShading] = []
    var height: CGFloat = 170

    /// Padded plot domain, so the curve never touches the frame.
    private var domain: (lo: Double, hi: Double) {
        let lo = min(samples.min() ?? 0, datumValue)
        let hi = max(samples.max() ?? 1, datumValue)
        let pad = max((hi - lo) * 0.14, 0.05)
        return (lo - pad, hi + pad)
    }

    private func y(_ value: Double, in size: CGSize) -> CGFloat {
        let d = domain
        let span = max(d.hi - d.lo, 0.0001)
        return size.height * CGFloat(1 - (value - d.lo) / span)
    }

    private func x(_ fraction: Double, in size: CGSize) -> CGFloat {
        size.width * CGFloat(fraction)
    }

    private func point(_ i: Int, in size: CGSize) -> CGPoint {
        let f = Double(i) / Double(max(samples.count - 1, 1))
        return CGPoint(x: x(f, in: size), y: y(samples[i], in: size))
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let size = geo.size
                ZStack(alignment: .topLeading) {
                    // Twilight bands (nil-safe: nothing is drawn without input).
                    ForEach(Array(twilight.enumerated()), id: \.offset) { _, band in
                        theme.palette.ink.opacity(theme.isNight ? 0.05 : 0.045)
                            .frame(width: size.width * CGFloat(band.end - band.start))
                            .offset(x: size.width * CGFloat(band.start))
                    }

                    // Gridlines every 3 h.
                    Path { p in
                        for i in 1..<8 {
                            let gx = size.width * CGFloat(i) / 8
                            p.move(to: CGPoint(x: gx, y: 0))
                            p.addLine(to: CGPoint(x: gx, y: size.height))
                        }
                    }
                    .stroke(theme.palette.hairline, lineWidth: 1)

                    // Water.
                    Path { p in
                        guard !samples.isEmpty else { return }
                        p.move(to: CGPoint(x: 0, y: size.height))
                        for i in samples.indices { p.addLine(to: point(i, in: size)) }
                        p.addLine(to: CGPoint(x: size.width, y: size.height))
                        p.closeSubpath()
                    }
                    .fill(theme.palette.water.opacity(theme.palette.waterFillOpacity))

                    // Chart datum, labelled. A curve without a zero is a guess.
                    let datumY = y(datumValue, in: size)
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: datumY))
                        p.addLine(to: CGPoint(x: size.width, y: datumY))
                    }
                    .stroke(theme.palette.ebb.opacity(0.65),
                            style: StrokeStyle(lineWidth: 1, dash: [5, 4]))

                    // The waterline.
                    Path { p in
                        guard !samples.isEmpty else { return }
                        for i in samples.indices {
                            let pt = point(i, in: size)
                            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                        }
                    }
                    .stroke(theme.palette.water,
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                    Text("\(datumLabel) 0.00 \(unitLabel)")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.palette.ebb)
                        .offset(x: 6, y: min(datumY + 3, size.height - 14))

                    // Extremes, annotated in place.
                    ForEach(markers) { m in
                        let mx = x(m.x, in: size)
                        let my = markerY(m, in: size)
                        Circle()
                            .strokeBorder(theme.palette.water, lineWidth: 2.5)
                            .background(Circle().fill(theme.palette.surface))
                            .frame(width: 9, height: 9)
                            .position(x: mx, y: my)
                        VStack(spacing: 1) {
                            Text(m.time)
                                .font(MarineType.mono11)
                                .foregroundStyle(theme.palette.ink)
                            Text(theme.palette.signByGlyph
                                 ? (m.positive ? "▲\(m.value)" : "▼\(m.value)")
                                 : m.value)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(m.positive ? theme.palette.water : theme.palette.ebb)
                        }
                        .monospacedDigit()
                        .fixedSize()
                        .position(x: min(max(mx, 26), size.width - 26),
                                  y: labelPosition(my, positive: m.positive, in: size,
                                                   offset: 26, topInset: 2))
                    }

                    // Now.
                    if let nowX {
                        let nx = x(nowX, in: size)
                        Rectangle()
                            .fill(theme.palette.ink)
                            .frame(width: 1.5, height: size.height)
                            .position(x: nx, y: size.height / 2)
                        if let nowLabel {
                            Text(nowLabel)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(theme.palette.surface)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(theme.palette.ink,
                                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                .fixedSize()
                                .position(x: min(max(nx, 46), size.width - 46), y: 10)
                        }
                    }
                }
            }
            .frame(height: height)
            .padding(.top, 26)

            HourAxis(labels: ["00", "03", "06", "09", "12", "15", "18", "21", "24"])
        }
        .background(theme.palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: MarineMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: MarineMetrics.cardRadius, style: .continuous)
            .strokeBorder(theme.palette.hairline, lineWidth: 1))
        .accessibilityIdentifier("chart.tideCurve")
    }

    /// Placed from the Kit's own extreme height, not the nearest sample — see the
    /// note on `ChartMarker.y`.
    private func markerY(_ m: ChartMarker, in size: CGSize) -> CGFloat {
        y(m.y, in: size)
    }

}

// MARK: - Current graph

/// Signed velocity: flood above the zero line, ebb below, both filled so the
/// direction of the stream is readable at a glance rather than decoded.
struct CurrentGraph: View {
    @Environment(\.marine) private var theme

    /// Velocities in knots, already converted by the view model.
    let samples: [Double]
    let markers: [ChartMarker]
    let nowX: Double?
    let floodLabel: String
    let ebbLabel: String
    var height: CGFloat = 150

    private var peak: Double { max(samples.map(abs).max() ?? 1, 0.001) }

    private func y(_ v: Double, in size: CGSize) -> CGFloat {
        size.height * CGFloat(0.5 - (v / peak) * 0.44)
    }

    private func point(_ i: Int, in size: CGSize) -> CGPoint {
        CGPoint(x: size.width * CGFloat(i) / CGFloat(max(samples.count - 1, 1)),
                y: y(samples[i], in: size))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(floodLabel.uppercased())
                    .font(MarineType.badge).tracking(0.8)
                    .foregroundStyle(theme.palette.signByGlyph ? theme.palette.ink : theme.palette.flood)
                Spacer()
                Text(ebbLabel.uppercased())
                    .font(MarineType.badge).tracking(0.8)
                    .foregroundStyle(theme.palette.signByGlyph ? theme.palette.ink : theme.palette.ebb)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            GeometryReader { geo in
                let size = geo.size
                let zero = size.height / 2
                ZStack(alignment: .topLeading) {
                    Path { p in
                        for i in 1..<8 {
                            let gx = size.width * CGFloat(i) / 8
                            p.move(to: CGPoint(x: gx, y: 0))
                            p.addLine(to: CGPoint(x: gx, y: size.height))
                        }
                    }
                    .stroke(theme.palette.hairline, lineWidth: 1)

                    let area = Path { p in
                        guard !samples.isEmpty else { return }
                        p.move(to: CGPoint(x: 0, y: zero))
                        for i in samples.indices { p.addLine(to: point(i, in: size)) }
                        p.addLine(to: CGPoint(x: size.width, y: zero))
                        p.closeSubpath()
                    }
                    area.fill(theme.palette.flood.opacity(0.16))
                        .clipShape(Rectangle().path(in: CGRect(x: 0, y: 0,
                                                              width: size.width, height: zero)))
                    area.fill(theme.palette.ebb.opacity(0.16))
                        .clipShape(Rectangle().path(in: CGRect(x: 0, y: zero,
                                                               width: size.width, height: zero)))

                    Path { p in
                        p.move(to: CGPoint(x: 0, y: zero))
                        p.addLine(to: CGPoint(x: size.width, y: zero))
                    }
                    .stroke(theme.palette.ink.opacity(0.55), lineWidth: 1.5)

                    Path { p in
                        guard !samples.isEmpty else { return }
                        for i in samples.indices {
                            let pt = point(i, in: size)
                            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                        }
                    }
                    .stroke(theme.palette.water,
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                    ForEach(markers) { m in
                        let mx = size.width * CGFloat(m.x)
                        // From the Kit's own value, not the nearest sample — see ChartMarker.y.
                        let my = y(m.y, in: size)
                        if m.hollow {
                            Circle()
                                .strokeBorder(theme.palette.inkDim, lineWidth: 2)
                                .background(Circle().fill(theme.palette.surface))
                                .frame(width: 7, height: 7)
                                .position(x: mx, y: my)
                        } else {
                            Circle()
                                .fill(m.positive ? theme.palette.flood : theme.palette.ebb)
                                .frame(width: 8, height: 8)
                                .position(x: mx, y: my)
                            VStack(spacing: 1) {
                                Text(m.time).font(MarineType.mono10)
                                    .foregroundStyle(theme.palette.inkDim)
                                Text(m.value)
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(m.positive ? theme.palette.flood : theme.palette.ebb)
                            }
                            .fixedSize()
                            .position(x: min(max(mx, 26), size.width - 26),
                                      y: labelPosition(my, positive: m.positive, in: size,
                                                       offset: 24, topInset: 16))
                        }
                    }

                    if let nowX {
                        Rectangle()
                            .fill(theme.palette.ink)
                            .frame(width: 1.5, height: size.height)
                            .position(x: size.width * CGFloat(nowX), y: size.height / 2)
                    }
                }
            }
            .frame(height: height)

            HourAxis(labels: ["00", "03", "06", "09", "12", "15", "18", "21", "24"])
        }
        .background(theme.palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: MarineMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: MarineMetrics.cardRadius, style: .continuous)
            .strokeBorder(theme.palette.hairline, lineWidth: 1))
        .accessibilityIdentifier("chart.currentCurve")
    }
}

// MARK: - Variation dial

/// True north against magnetic north. Geometry from one number — the WMM
/// declination GeomagKit already returned.
struct VariationDial: View {
    @Environment(\.marine) private var theme
    /// Positive east.
    let declinationDeg: Double
    var size: CGFloat = 112

    var body: some View {
        Canvas { ctx, s in
            let c = CGPoint(x: s.width / 2, y: s.height / 2)
            let r = min(s.width, s.height) / 2 - 4

            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                       with: .color(theme.palette.hairline), lineWidth: 1.5)

            for i in 0..<12 {
                let a = Double(i) / 12 * 2 * .pi
                let long = i % 3 == 0
                let inner = r - (long ? 10 : 6)
                var p = Path()
                p.move(to: CGPoint(x: c.x + sin(a) * inner, y: c.y - cos(a) * inner))
                p.addLine(to: CGPoint(x: c.x + sin(a) * r, y: c.y - cos(a) * r))
                ctx.stroke(p, with: .color(theme.palette.ink.opacity(long ? 0.28 : 0.16)),
                           lineWidth: long ? 1.5 : 1)
            }

            var trueNorth = Path()
            trueNorth.move(to: c)
            trueNorth.addLine(to: CGPoint(x: c.x, y: c.y - r + 2))
            ctx.stroke(trueNorth, with: .color(theme.palette.inkDim),
                       style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))

            let a = declinationDeg * .pi / 180
            var magnetic = Path()
            magnetic.move(to: c)
            magnetic.addLine(to: CGPoint(x: c.x + sin(a) * (r - 2), y: c.y - cos(a) * (r - 2)))
            ctx.stroke(magnetic, with: .color(theme.palette.water),
                       style: StrokeStyle(lineWidth: 3, lineCap: .round))

            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)),
                     with: .color(theme.palette.ink))
        }
        .frame(width: size, height: size)
        .accessibilityIdentifier("chart.variationDial")
    }
}
