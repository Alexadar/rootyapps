import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// Marine Nav — watchOS chart treatment.
//
// PRESENTATION ONLY. Receives already-computed samples and events and maps them
// to points. No prediction, no interpolation of a physical quantity, no unit
// conversion.
//
// Deliberately NOT a shrunk `TideCurve`. At 200 pt wide the phone chart's
// gridlines, hour labels, datum caption, four annotated extremes and now-capsule
// collapse into mush. The watch curve keeps only what a glance uses:
//   · the waterline and its fill (the shape of the day)
//   · the datum, as a rule — labelled once, in the caption below, not on the plot
//   · the extremes, as bare dots (their numbers are in the list, not on the plot)
//   · the cursor: NOW, or the crown's scrub position
// Everything dropped is dropped on purpose, and is one scroll away as text.
// ─────────────────────────────────────────────────────────────────────────────

/// An extreme, reduced to what the plot needs. `y` carries the Kit's OWN value —
/// resolving it from the nearest sample put a high water visibly below its crest
/// on the phone once.
struct WatchCurveMark: Identifiable {
    let id: Int
    /// 0…1 across the window.
    let x: Double
    /// The value in plot units, from the Kit.
    let y: Double
    let positive: Bool
}

/// 24 h of predicted height, wrist-sized.
struct WatchTideCurve: View {
    @Environment(\.watchTheme) private var theme

    /// `Harmonics.heights` output — 97 samples spanning 00:00…24:00 inclusive, so
    /// index/96 and time/24 h agree. (96 samples mapped as i/95 was a 15-minute
    /// error at the right edge on the phone.)
    let samples: [Double]
    let marks: [WatchCurveMark]
    /// Chart datum in plot units — 0.0 for MLLW. Drawn where the real zero is.
    let datumValue: Double
    /// Cursor position 0…1: NOW, or where the crown has scrubbed to. Nil when the
    /// window is not today and nothing is being scrubbed.
    let cursorX: Double?
    /// True while the crown is driving the cursor: the cursor thickens and the
    /// dots recede.
    let scrubbing: Bool
    var height: CGFloat = 52

    private var domain: (lo: Double, hi: Double) {
        let lo = min(samples.min() ?? 0, datumValue)
        let hi = max(samples.max() ?? 1, datumValue)
        let pad = max((hi - lo) * 0.12, 0.05)
        return (lo - pad, hi + pad)
    }

    private func y(_ v: Double, in size: CGSize) -> CGFloat {
        let d = domain
        return size.height * CGFloat(1 - (v - d.lo) / max(d.hi - d.lo, 0.0001))
    }

    private func point(_ i: Int, in size: CGSize) -> CGPoint {
        CGPoint(x: size.width * CGFloat(i) / CGFloat(max(samples.count - 1, 1)),
                y: y(samples[i], in: size))
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                // Fill. Dropped in the always-on state — a large lit area is
                // exactly what the dimmed display is trying to avoid.
                if !theme.luminanceReduced {
                    Path { p in
                        guard !samples.isEmpty else { return }
                        p.move(to: CGPoint(x: 0, y: size.height))
                        for i in samples.indices { p.addLine(to: point(i, in: size)) }
                        p.addLine(to: CGPoint(x: size.width, y: size.height))
                        p.closeSubpath()
                    }
                    .fill(theme.palette.water.opacity(theme.palette.waterFillOpacity))
                }

                // Datum. A curve with no zero is a guess. Dashed in normal use,
                // solid-dim when dimmed (dashes smear on the ambient display).
                let dy = y(datumValue, in: size)
                Path { p in
                    p.move(to: CGPoint(x: 0, y: dy))
                    p.addLine(to: CGPoint(x: size.width, y: dy))
                }
                .stroke(theme.palette.ebb.opacity(theme.luminanceReduced ? 0.35 : 0.65),
                        style: theme.luminanceReduced
                            ? StrokeStyle(lineWidth: 1)
                            : StrokeStyle(lineWidth: 1, dash: [4, 3]))

                // The waterline.
                Path { p in
                    guard !samples.isEmpty else { return }
                    for i in samples.indices {
                        let pt = point(i, in: size)
                        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                }
                .stroke(theme.luminanceReduced ? theme.palette.water.opacity(0.7)
                                               : theme.palette.water,
                        style: StrokeStyle(lineWidth: theme.palette.stroke,
                                           lineCap: .round, lineJoin: .round))

                // Extremes: position only. High water is a dot ABOVE the line's
                // crest, low water BELOW its trough — readable with no hue.
                if !theme.luminanceReduced {
                    ForEach(marks) { m in
                        Circle()
                            .fill(theme.palette.signByGlyph
                                  ? theme.palette.ink
                                  : (m.positive ? theme.palette.water : theme.palette.ebb))
                            .frame(width: 4, height: 4)
                            .opacity(scrubbing ? 0.45 : 1)
                            .position(x: size.width * CGFloat(m.x),
                                      y: y(m.y, in: size) + (m.positive ? -5 : 5))
                    }
                }

                if let cursorX {
                    let cx = size.width * CGFloat(cursorX)
                    Rectangle()
                        .fill(theme.ambientInk)
                        .frame(width: scrubbing ? 2 : 1.5, height: size.height)
                        .position(x: cx, y: size.height / 2)
                    // The cursor's own dot rides the curve, so the readout above
                    // and the plot agree at a glance.
                    let i = Int((cursorX * Double(max(samples.count - 1, 1))).rounded())
                    if samples.indices.contains(i) {
                        Circle()
                            .fill(theme.ambientInk)
                            .frame(width: 6, height: 6)
                            .position(x: cx, y: y(samples[i], in: size))
                    }
                }
            }
        }
        .frame(height: height)
        // Not decorative: VoiceOver gets the day's shape as words from the
        // caller's label. The chart itself carries the identifier for UI tests.
        .accessibilityIdentifier("chart.tideCurve")
    }
}

/// Signed velocity. Flood ABOVE the zero rule, ebb BELOW it — position, not
/// colour, exactly as on the phone.
struct WatchCurrentCurve: View {
    @Environment(\.watchTheme) private var theme
    /// Knots, already converted by the view model.
    let samples: [Double]
    let cursorX: Double?
    let scrubbing: Bool
    var height: CGFloat = 52

    private var peak: Double { max(samples.map(abs).max() ?? 1, 0.001) }

    private func y(_ v: Double, in size: CGSize) -> CGFloat {
        size.height * CGFloat(0.5 - (v / peak) * 0.42)
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let zero = size.height / 2
            ZStack(alignment: .topLeading) {
                if !theme.luminanceReduced {
                    let area = Path { p in
                        guard !samples.isEmpty else { return }
                        p.move(to: CGPoint(x: 0, y: zero))
                        for i in samples.indices {
                            p.addLine(to: CGPoint(
                                x: size.width * CGFloat(i) / CGFloat(max(samples.count - 1, 1)),
                                y: y(samples[i], in: size)))
                        }
                        p.addLine(to: CGPoint(x: size.width, y: zero))
                        p.closeSubpath()
                    }
                    area.fill(theme.palette.flood.opacity(0.20))
                        .clipShape(Rectangle().path(in: CGRect(x: 0, y: 0,
                                                              width: size.width, height: zero)))
                    area.fill(theme.palette.ebb.opacity(0.20))
                        .clipShape(Rectangle().path(in: CGRect(x: 0, y: zero,
                                                               width: size.width, height: zero)))
                }

                Path { p in
                    p.move(to: CGPoint(x: 0, y: zero))
                    p.addLine(to: CGPoint(x: size.width, y: zero))
                }
                .stroke(theme.ambientInk.opacity(0.5), lineWidth: 1.5)

                Path { p in
                    guard !samples.isEmpty else { return }
                    for i in samples.indices {
                        let pt = CGPoint(
                            x: size.width * CGFloat(i) / CGFloat(max(samples.count - 1, 1)),
                            y: y(samples[i], in: size))
                        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                }
                .stroke(theme.luminanceReduced ? theme.palette.water.opacity(0.7)
                                               : theme.palette.water,
                        style: StrokeStyle(lineWidth: theme.palette.stroke,
                                           lineCap: .round, lineJoin: .round))

                if let cursorX {
                    Rectangle()
                        .fill(theme.ambientInk)
                        .frame(width: scrubbing ? 2 : 1.5, height: size.height)
                        .position(x: size.width * CGFloat(cursorX), y: zero)
                }
            }
        }
        .frame(height: height)
        .accessibilityIdentifier("chart.currentCurve")
    }
}

/// True vs magnetic north, wrist-sized: the phone's `VariationDial` with its
/// twelve tick marks and dashed true-north reduced to two needles and a cardinal
/// ring, because at 60 pt the ticks merge.
struct WatchVariationDial: View {
    @Environment(\.watchTheme) private var theme
    /// Positive east. From `WMM.field` — geometry only here.
    let declinationDeg: Double
    var size: CGFloat = 62

    var body: some View {
        Canvas { ctx, s in
            let c = CGPoint(x: s.width / 2, y: s.height / 2)
            let r = min(s.width, s.height) / 2 - 2

            if !theme.luminanceReduced {
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r,
                                                  width: r * 2, height: r * 2)),
                           with: .color(theme.palette.hairline), lineWidth: 1)
            }
            for i in 0..<4 {
                let a = Double(i) / 4 * 2 * .pi
                var p = Path()
                p.move(to: CGPoint(x: c.x + sin(a) * (r - 5), y: c.y - cos(a) * (r - 5)))
                p.addLine(to: CGPoint(x: c.x + sin(a) * r, y: c.y - cos(a) * r))
                ctx.stroke(p, with: .color(theme.ambientInk.opacity(0.35)), lineWidth: 1.5)
            }
            var trueN = Path()
            trueN.move(to: c)
            trueN.addLine(to: CGPoint(x: c.x, y: c.y - r + 1))
            ctx.stroke(trueN, with: .color(theme.palette.inkDim),
                       style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))

            let a = declinationDeg * .pi / 180
            var mag = Path()
            mag.move(to: c)
            mag.addLine(to: CGPoint(x: c.x + sin(a) * (r - 1), y: c.y - cos(a) * (r - 1)))
            ctx.stroke(mag, with: .color(theme.palette.water),
                       style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 2.5, y: c.y - 2.5, width: 5, height: 5)),
                     with: .color(theme.ambientInk))
        }
        .frame(width: size, height: size)
        .accessibilityIdentifier("chart.variationDial")
    }
}
