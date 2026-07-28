import SwiftUI
import SpaceWeatherFeed
import Charts
import GeomagKit
import HpoKit

// Replaces Views/Charts.swift. Same call sites; theme-aware, severity-coloured internals.

/// Chart heights are phone-sized by default; a 46mm watch is only ~248pt tall, so a
/// 200pt chart pushes everything below it off the screen.
private enum ChartH {
    #if os(watchOS)
    static let hero: CGFloat = 104
    static let series: CGFloat = 88
    #else
    static let hero: CGFloat = 200
    static let series: CGFloat = 170
    #endif
}

// MARK: - Hp30 match timeline (GFZ, 30-minute cadence) — the hero

/// The differentiator framed as a live match feed: brand-tinted line + area fade,
/// the G1 threshold as a caution rule, and a live point on the newest reading.
struct Hp30Chart: View {
    @Environment(\.sw) private var sw
    let readings: [Hpo.Reading]

    var body: some View {
        Chart {
            ForEach(Array(readings.enumerated()), id: \.offset) { _, r in
                AreaMark(x: .value("Time", r.time), y: .value("Hp30", r.value))
                    .foregroundStyle(.linearGradient(colors: [sw.brand.opacity(0.28), .clear],
                                                     startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Time", r.time), y: .value("Hp30", r.value))
                    .foregroundStyle(sw.brand)
                    .interpolationMethod(.monotone)
            }
            RuleMark(y: .value("G1", 5))
                .foregroundStyle(sw.caution.opacity(0.6))
                .lineStyle(.init(lineWidth: 1, dash: [4, 3]))
                .annotation(position: .top, alignment: .leading) {
                    Text("G1")
                        .font(.system(.caption2, design: .monospaced).weight(.semibold))
                        .foregroundStyle(sw.caution)
                }
            if let last = readings.last {
                PointMark(x: .value("Time", last.time), y: .value("Hp30", last.value))
                    .foregroundStyle(sw.brand)
                    .symbolSize(60)
            }
        }
        .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 12)) { _ in
            AxisGridLine().foregroundStyle(sw.hairline)
            AxisValueLabel(format: .dateTime.hour().locale(SWLanguage.sharedLocale), centered: false)
                .foregroundStyle(sw.textTertiary).font(.system(.caption2, design: .monospaced))
        } }
        .chartYAxis { AxisMarks { _ in
            AxisGridLine().foregroundStyle(sw.hairline)
            AxisValueLabel()
                .foregroundStyle(sw.textTertiary).font(.system(.caption2, design: .monospaced))
        } }
        .padding(10)
        .background(sw.grouped, in: ChamferBox(cut: 8, radius: SWM.rTile))
        .frame(height: ChartH.hero)
        .accessibilityLabel(a11y)
    }

    private var a11y: String {
        guard let last = readings.last else { return "Hp30 chart, no data" }
        return "Hp30 chart, latest \(Fmt.num(last.value, 2)), G1 threshold at 5"
    }
}

// MARK: - Kp scoreboard (NOAA: observed + forecast)

/// Quiet bars stay neutral steel; a bar takes severity colour only when a level is in
/// play. Forecast bars ghost to 40%.
struct KpBarChart: View {
    @Environment(\.sw) private var sw
    let series: [KpSample]
    var showForecast = true

    private func barColor(_ kp: Double) -> Color {
        let g = Geomag.gScale(forKp: kp)
        return g > 0 ? sw.severity(g) : sw.side(.link).opacity(0.7)
    }

    var body: some View {
        Chart(series.filter { showForecast || !$0.predicted }) { s in
            BarMark(x: .value("Time", s.time, unit: .hour), y: .value("Kp", s.kp))
                .foregroundStyle(barColor(s.kp).opacity(s.predicted ? 0.4 : 1))
                .cornerRadius(1.5)
        }
        .chartYScale(domain: 0...9)
        .chartYAxis { AxisMarks(values: [0, 3, 5, 7, 9]) { _ in
            AxisGridLine().foregroundStyle(sw.hairline)
            AxisValueLabel()
                .foregroundStyle(sw.textTertiary).font(.system(.caption2, design: .monospaced))
        } }
        .chartXAxis { AxisMarks(values: .stride(by: .day, count: 1)) { _ in
            AxisGridLine().foregroundStyle(sw.hairline)
            AxisValueLabel(format: .dateTime.weekday().locale(SWLanguage.sharedLocale), centered: true)
                .foregroundStyle(sw.textTertiary).font(.system(.caption2, design: .monospaced))
        } }
        .padding(10)
        .background(sw.grouped, in: ChamferBox(cut: 8, radius: SWM.rTile))
        .frame(height: ChartH.series)
        .accessibilityLabel(a11y)
    }

    private var a11y: String {
        guard let now = series.last(where: { !$0.predicted }) else { return "Kp chart, no data" }
        return "Kp bar chart, current \(Fmt.num(now.kp, 1))"
    }
}

// MARK: - X-ray flux (NOAA GOES, log scale)

/// The flux line is off-white — the data; the C/M/X class rules carry the meaning
/// (normal / caution / warning).
struct XRayFluxChart: View {
    @Environment(\.sw) private var sw
    let series: [FluxSample]

    var body: some View {
        Chart {
            ForEach(series) { s in
                LineMark(x: .value("Time", s.time), y: .value("Flux", max(s.flux, 1e-9)))
                    .foregroundStyle(sw.textPrimary.opacity(0.85))
                    .interpolationMethod(.monotone)
            }
            ForEach(bands, id: \.1) { level, name, color in
                RuleMark(y: .value("Class", level))
                    .foregroundStyle(color.opacity(0.5))
                    .lineStyle(.init(lineWidth: 0.75, dash: [3, 3]))
                    .annotation(position: .trailing, alignment: .leading) {
                        Text(name)
                            .font(.system(.caption2, design: .monospaced).weight(.semibold))
                            .foregroundStyle(color)
                    }
            }
        }
        .chartYScale(domain: 1e-9...1e-3, type: .log)
        .chartYAxis { AxisMarks(values: [1e-8, 1e-6, 1e-4]) { _ in
            AxisGridLine().foregroundStyle(sw.hairline)
            AxisValueLabel()
                .foregroundStyle(sw.textTertiary).font(.system(.caption2, design: .monospaced))
        } }
        .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
            AxisGridLine().foregroundStyle(sw.hairline)
            AxisValueLabel(format: .dateTime.hour().locale(SWLanguage.sharedLocale))
                .foregroundStyle(sw.textTertiary).font(.system(.caption2, design: .monospaced))
        } }
        .padding(10)
        .background(sw.grouped, in: ChamferBox(cut: 8, radius: SWM.rTile))
        .frame(height: ChartH.series)
        .accessibilityLabel(a11y)
    }

    private var bands: [(Double, String, Color)] {
        [(1e-6, "C", sw.normal), (1e-5, "M", sw.caution), (1e-4, "X", sw.warning)]
    }

    private var a11y: String {
        guard let last = series.last else { return "X-ray flux chart, no data" }
        return "X-ray flux chart, current class \(last.label)"
    }
}
