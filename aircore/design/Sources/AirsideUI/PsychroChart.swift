import SwiftUI
import AirsideKit

/// The psychrometric chart. Dry bulb (x) vs humidity ratio (y), constant-RH curves,
/// and a draggable state point. Both directions work: bind `state` and edit it
/// numerically to move the point, or drag the point to update `state`.
public struct PsychroChart: View {
    @Binding public var dryBulb: Double
    @Binding public var relHumidity: Double
    public var altitude: Altitude
    public var showEnthalpy: Bool
    public var interactive: Bool

    public init(dryBulb: Binding<Double>, relHumidity: Binding<Double>,
                altitude: Altitude, showEnthalpy: Bool = false, interactive: Bool = true) {
        self._dryBulb = dryBulb; self._relHumidity = relHumidity
        self.altitude = altitude; self.showEnthalpy = showEnthalpy; self.interactive = interactive
    }

    private let tMin = 40.0, tMax = 110.0, wMax = 0.026

    private func x(_ t: Double, _ w: CGFloat) -> CGFloat { CGFloat((t - tMin) / (tMax - tMin)) * w }
    private func y(_ ratio: Double, _ h: CGFloat) -> CGFloat { h - CGFloat(min(ratio, wMax) / wMax) * h }

    public var body: some View {
        GeometryReader { geo in
            let W = geo.size.width, H = geo.size.height
            let P = altitude.pressurePa
            ZStack {
                // constant-RH curves
                ForEach(Array(stride(from: 20, through: 80, by: 20)), id: \.self) { rh in
                    Path { p in
                        var started = false
                        for t in stride(from: tMin, through: tMax, by: 2) {
                            let w = Psychrometrics.humidityRatio(dryBulbF: t, rh: Double(rh) / 100, pressurePa: P)
                            let pt = CGPoint(x: x(t, W), y: y(min(w, wMax), H))
                            if started { p.addLine(to: pt) } else { p.move(to: pt); started = true }
                            if w > wMax { break }
                        }
                    }.stroke(DS.border, lineWidth: 1)
                }
                // saturation curve (100% RH)
                Path { p in
                    var started = false
                    for t in stride(from: tMin, through: tMax, by: 2) {
                        let w = Psychrometrics.humidityRatio(dryBulbF: t, rh: 1, pressurePa: P)
                        let pt = CGPoint(x: x(t, W), y: y(min(w, wMax), H))
                        if started { p.addLine(to: pt) } else { p.move(to: pt); started = true }
                        if w > wMax { break }
                    }
                }.stroke(Color(hex: 0x6D94AD), lineWidth: 1.6)

                // state point A
                let w = Psychrometrics.humidityRatio(dryBulbF: dryBulb, rh: relHumidity / 100, pressurePa: P)
                let cx = x(dryBulb, W), cy = y(min(w, wMax), H)
                Circle().fill(DS.water).frame(width: 13, height: 13).position(x: cx, y: cy)
                    .accessibilityLabel("State A, \(Int(dryBulb)) degrees, \(Int(relHumidity)) percent relative humidity")
            }
            .contentShape(Rectangle())
            .gesture(interactive ? DragGesture().onChanged { g in
                let t = tMin + Double(g.location.x / W) * (tMax - tMin)
                dryBulb = min(max(t, tMin), tMax)
                // invert humidity ratio at this dry bulb back to RH
                let targetW = Double((H - g.location.y) / H) * wMax
                let pw = targetW * P / (0.62198 + targetW)
                let rh = pw / Psychrometrics.satPressure(dryBulbF: dryBulb)
                relHumidity = min(max(rh * 100, 1), 100)
            } : nil)
        }
        .background(DS.card)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusCard).stroke(DS.border, lineWidth: 1))
    }
}
