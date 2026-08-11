import SwiftUI
import PsychroKit
import UnitsKit

/// A point to draw on the chart.
struct ChartPoint: Identifiable, Equatable {
    enum Role: String, Equatable {
        case a, b, mixed

        var colour: Color {
            switch self {
            case .a: return DS.water
            case .b: return DS.stateB
            case .mixed: return DS.mixed
            }
        }
        var label: String {
            switch self {
            case .a: return "State A"
            case .b: return "State B"
            case .mixed: return "Mixed state"
            }
        }
    }

    let role: Role
    let state: MoistAir
    var id: String { role.rawValue }
}

/// The psychrometric chart.
///
/// ## What it is
///
/// Dry-bulb temperature across, humidity ratio up, with the saturation curve and constant-relative-
/// humidity curves drawn from the same ``PsychroKit`` the readouts use — so the curve a point sits
/// on and the number beside it cannot disagree. Every curve is recomputed at the site's barometric
/// pressure, which is why the chart visibly changes shape when the elevation does.
///
/// ## Legibility over completeness
///
/// A paper psychrometric chart carries five overlaid scales and is a wall poster. Reproducing that
/// at 393 points wide produces a grey smear. So the chart is drawn in layers and the layers appear
/// as there is room for them: saturation and RH curves always; enthalpy obliques and the grid
/// labels only when the chart is given real width. Nothing is hidden behind a gesture the user has
/// to discover — the chart simply shows what is readable at the size it has been given.
///
/// ## Both directions, neither second-class
///
/// Typing moves the point; dragging the point rewrites the numbers. The drag is clamped to the
/// saturation curve, because the region above it is not air. A drag also switches the two knowns to
/// dry bulb and humidity ratio — the pair the pointer is actually specifying — so the pickers and
/// the pointer never fight over the same state.
///
/// ## VoiceOver
///
/// A chart that is invisible to VoiceOver is a failed screen. Each state point is its own
/// accessibility element with a full spoken value, and the chart itself carries a summary, so the
/// whole thing is reachable by swipe without sight of it.
struct PsychroChartView: View {

    let points: [ChartPoint]
    let pressure: Double
    let system: UnitSystem
    /// Nil makes the chart read-only — the iPad inspector and the Mac sidebar both show charts
    /// that are views onto other tools' numbers.
    var onDrag: ((_ dryBulb: Double, _ humidityRatio: Double) -> Void)?

    /// Chart bounds in SI. −10 °C to 55 °C spans everything from a winter outdoor-air condition to
    /// a hot roof; 0 to 0.030 kg/kg covers saturated air at the top of that range.
    private let minDryBulb = -10.0
    private let maxDryBulb = 55.0
    private let maxHumidityRatio = 0.030

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let detailed = size.width >= 420

            ZStack {
                Canvas { context, canvasSize in
                    draw(in: &context, size: canvasSize, detailed: detailed)
                }
                .accessibilityHidden(true)

                ForEach(points) { point in
                    marker(for: point, in: size)
                }
            }
            .contentShape(Rectangle())
            .gesture(onDrag.map { handler in
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard let solved = state(at: value.location, in: size) else { return }
                        handler(solved.dryBulb, solved.humidityRatio)
                    }
            })
        }
        .background(DS.card)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusCard).stroke(DS.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Psychrometric chart")
        .accessibilityIdentifier("psychro.chart")
    }

    // MARK: - Mapping

    private func x(_ dryBulb: Double, _ width: CGFloat) -> CGFloat {
        CGFloat((dryBulb - minDryBulb) / (maxDryBulb - minDryBulb)) * width
    }

    private func y(_ humidityRatio: Double, _ height: CGFloat) -> CGFloat {
        height - CGFloat(min(humidityRatio, maxHumidityRatio) / maxHumidityRatio) * height
    }

    /// Turn a touch into a state, clamped to the chart and to the saturation curve.
    private func state(at location: CGPoint, in size: CGSize) -> (dryBulb: Double,
                                                                  humidityRatio: Double)? {
        guard size.width > 0, size.height > 0 else { return nil }
        let dryBulb = min(max(minDryBulb + Double(location.x / size.width)
                              * (maxDryBulb - minDryBulb), minDryBulb), maxDryBulb)
        let raw = Double((size.height - location.y) / size.height) * maxHumidityRatio

        // Above the saturation curve is fog, not air. Clamp rather than refuse: a thumb that
        // overshoots the curve should land on it, not throw the screen into an error state.
        let saturation = (try? Psychrometrics.saturationHumidityRatio(dryBulb: dryBulb,
                                                                      pressure: pressure)) ?? raw
        return (dryBulb, min(max(raw, 0), saturation))
    }

    // MARK: - Drawing

    private func draw(in context: inout GraphicsContext, size: CGSize, detailed: Bool) {
        drawRelativeHumidityCurves(in: &context, size: size, detailed: detailed)
        if detailed { drawEnthalpyObliques(in: &context, size: size) }
        drawSaturationCurve(in: &context, size: size)
        drawGrid(in: &context, size: size, detailed: detailed)
        drawProcessLine(in: &context, size: size)
    }

    private func curve(relativeHumidity: Double, size: CGSize) -> Path {
        var path = Path()
        var started = false
        for step in stride(from: minDryBulb, through: maxDryBulb, by: 0.5) {
            guard let saturation = try? Psychrometrics.saturationPressure(dryBulb: step),
                  let ratio = try? Psychrometrics.humidityRatio(
                    vapourPressure: relativeHumidity * saturation, pressure: pressure)
            else { continue }
            if ratio > maxHumidityRatio { break }
            let point = CGPoint(x: x(step, size.width), y: y(ratio, size.height))
            if started { path.addLine(to: point) } else { path.move(to: point); started = true }
        }
        return path
    }

    private func drawRelativeHumidityCurves(in context: inout GraphicsContext, size: CGSize,
                                            detailed: Bool) {
        let steps: [Double] = detailed ? [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9]
                                       : [0.2, 0.4, 0.6, 0.8]
        for relativeHumidity in steps {
            context.stroke(curve(relativeHumidity: relativeHumidity, size: size),
                           with: .color(DS.border), lineWidth: 1)
        }
    }

    private func drawSaturationCurve(in context: inout GraphicsContext, size: CGSize) {
        context.stroke(curve(relativeHumidity: 1, size: size),
                       with: .color(DS.ink2), lineWidth: 1.8)
    }

    /// Constant-enthalpy lines. Nearly straight, and nearly parallel to the wet-bulb lines — which
    /// is exactly why the solver refuses to take wet bulb and enthalpy as a pair.
    private func drawEnthalpyObliques(in context: inout GraphicsContext, size: CGSize) {
        for enthalpy in stride(from: 0.0, through: 120.0, by: 20.0) {
            var path = Path()
            var started = false
            for step in stride(from: minDryBulb, through: maxDryBulb, by: 1.0) {
                let ratio = Psychrometrics.humidityRatio(enthalpy: enthalpy, dryBulb: step)
                guard ratio >= 0, ratio <= maxHumidityRatio else { continue }
                guard let saturation = try? Psychrometrics.saturationHumidityRatio(
                    dryBulb: step, pressure: pressure), ratio <= saturation else { continue }
                let point = CGPoint(x: x(step, size.width), y: y(ratio, size.height))
                if started { path.addLine(to: point) } else { path.move(to: point); started = true }
            }
            context.stroke(path, with: .color(DS.border.opacity(0.7)),
                           style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
        }
    }

    private func drawGrid(in context: inout GraphicsContext, size: CGSize, detailed: Bool) {
        let step: Double = detailed ? 5 : 10
        for dryBulb in stride(from: minDryBulb, through: maxDryBulb, by: step) {
            var path = Path()
            path.move(to: CGPoint(x: x(dryBulb, size.width), y: 0))
            path.addLine(to: CGPoint(x: x(dryBulb, size.width), y: size.height))
            context.stroke(path, with: .color(DS.border.opacity(0.5)), lineWidth: 0.5)
        }
    }

    /// The line between two states — a mixing process, drawn as the straight line it is.
    private func drawProcessLine(in context: inout GraphicsContext, size: CGSize) {
        guard points.count >= 2,
              let a = points.first(where: { $0.role == .a }),
              let b = points.first(where: { $0.role == .b }) else { return }
        var path = Path()
        path.move(to: position(of: a.state, in: size))
        path.addLine(to: position(of: b.state, in: size))
        context.stroke(path, with: .color(DS.mixed),
                       style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
    }

    private func position(of state: MoistAir, in size: CGSize) -> CGPoint {
        CGPoint(x: x(state.dryBulb, size.width), y: y(state.humidityRatio, size.height))
    }

    // MARK: - Markers

    @ViewBuilder
    private func marker(for point: ChartPoint, in size: CGSize) -> some View {
        let centre = position(of: point.state, in: size)
        ZStack {
            Circle().fill(DS.card).frame(width: 17, height: 17)
            Circle().fill(point.role.colour).frame(width: 11, height: 11)
        }
        .position(centre)
        .animation(reduceMotion ? nil : .interactiveSpring(duration: 0.15), value: centre)
        .accessibilityElement()
        // Everything in the label. macOS does not publish `accessibilityValue` for this element,
        // so a split label/value announced "State A" and nothing else — the chart's entire content,
        // silent, on the platform where a chart is most usable. Same defect as `ResultTile`.
        .accessibilityLabel("\(point.role.label), \(spokenValue(of: point.state))")
        .accessibilityIdentifier("psychro.point.\(point.role.rawValue)")
    }

    private func spokenValue(of state: MoistAir) -> String {
        var parts = [
            "dry bulb \(Fmt.spoken(si: state.dryBulb, .temperature, system))",
            "relative humidity \(Fmt.spoken(si: state.relativeHumidity, .relativeHumidity, system))",
            "wet bulb \(Fmt.spoken(si: state.wetBulb, .temperature, system))",
        ]
        if let dewPoint = state.dewPoint {
            parts.append("dew point \(Fmt.spoken(si: dewPoint, .temperature, system))")
        }
        parts.append("enthalpy \(Fmt.spoken(si: state.enthalpy, .enthalpy, system))")
        return parts.joined(separator: ", ")
    }
}
