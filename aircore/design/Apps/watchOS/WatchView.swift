import SwiftUI
import AirsideKit
import AirsideUI

/// watchOS — the call: include, minimal. One crown-driven conversion
/// (dry bulb + RH → dew point / wet bulb) and a readout of the last phone state.
/// No chart on the wrist; the Digital Crown is the primary input.
@main struct AirsideWatchApp: App {
    var body: some Scene { WindowGroup { WatchView() } }
}

struct WatchView: View {
    @State private var rh = 50.0        // crown-driven
    @State private var db = 75.0        // tap to change
    private var s: PsychroState { Psychrometrics.solve(dryBulbF: db, relHumidityPercent: rh, altitude: .denver) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Dew point").font(DS.ui(11, .semibold)).foregroundColor(Color(hex: 0x8FB0C8))
            Text("\(s.dewPoint.formatted(.number.precision(.fractionLength(1))))°")
                .font(DS.number(42, .semibold)).foregroundColor(.white).monospacedDigit()
            Text("WB \(s.wetBulb.formatted(.number.precision(.fractionLength(1))))° · h \(s.enthalpy.formatted(.number.precision(.fractionLength(1))))")
                .font(DS.number(12)).foregroundColor(Color(hex: 0xC7D6E4))
            Spacer()
            HStack {
                crownReadout("RH — crown", "\(Int(rh))%", color: Color(hex: 0x41B6E6))
                crownReadout("DB — tap", "\(Int(db))°", color: .white)
            }
            .padding(8)
            .background(Color(hex: 0x12222F))
            .clipShape(RoundedRectangle(cornerRadius: 11))
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.ignoresSafeArea())
        // Digital Crown drives RH — the fastest path to a value.
        .focusable()
        .digitalCrownRotation($rh, from: 1, through: 100, by: 1, sensitivity: .medium, isContinuous: false)
    }

    func crownReadout(_ label: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(DS.ui(9, .semibold)).foregroundColor(Color(hex: 0x8FB0C8))
            Text(value).font(DS.number(16)).foregroundColor(color)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
