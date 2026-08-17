import SwiftUI
import AirsideKit
import AirsideUI

/// iPadOS — the chart as a workspace. Chart and states side by side, mixing line
/// and multiple states comparable at once.
@main struct AirsideiPadApp: App {
    var body: some Scene { WindowGroup { ChartWorkspaceView() } }
}

struct ChartWorkspaceView: View {
    @State private var db = 75.0
    @State private var rh = 50.0
    @State private var altitude = Altitude.denver
    @State private var unit: UnitSystem = .ip

    private var a: PsychroState { Psychrometrics.solve(dryBulbF: 75, relHumidityPercent: 50, altitude: altitude) }
    private var b: PsychroState { Psychrometrics.solve(dryBulbF: 95, relHumidityPercent: 40, altitude: altitude) }

    var body: some View {
        HStack(spacing: 0) {
            // State inspector
            VStack(spacing: 11) {
                StateCard(letter: "A", name: "Return air", cfm: "7,500 CFM", accent: DS.water, s: a)
                StateCard(letter: "B", name: "Outdoor air", cfm: "2,500 CFM", accent: DS.stateB, s: b)
                MixedCard(a: a, cfmA: 7500, b: b, cfmB: 2500, altitude: altitude)
                Spacer()
                HStack(spacing: 8) {
                    exportButton("Copy table"); exportButton("Export CSV")
                }
            }
            .padding(16).frame(width: 320)
            .background(Color(hex: 0xE9F1F7))
            .overlay(Rectangle().frame(width: 1).foregroundColor(DS.border), alignment: .trailing)

            // Chart
            PsychroChart(dryBulb: $db, relHumidity: $rh, altitude: altitude, showEnthalpy: true)
                .padding(16)
        }
        .background(DS.breeze.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack { AltitudeChip(altitude: altitude) {}; UnitToggle(system: $unit) }
            }
        }
    }
    func exportButton(_ t: String) -> some View {
        Text(t).font(DS.ui(12, .semibold)).foregroundColor(DS.ink)
            .frame(maxWidth: .infinity).padding(.vertical, 9)
            .background(DS.card).overlay(RoundedRectangle(cornerRadius: 10).stroke(DS.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct StateCard: View {
    var letter: String, name: String, cfm: String, accent: Color, s: PsychroState
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack { Text("\(letter) — \(name)").font(DS.ui(13, .bold)).foregroundColor(DS.ink)
                Spacer(); Text(cfm).font(DS.number(11)).foregroundColor(Color(hex: 0x7F9FB5)) }
            HStack(spacing: 14) {
                Text("\(s.dryBulb.formatted(.number.precision(.fractionLength(1))))°").font(DS.number(20)).foregroundColor(DS.ink)
                Text("\(Int(s.relHumidity))%").font(DS.number(20)).foregroundColor(DS.ink)
            }
            Text("WB \(s.wetBulb.formatted(.number.precision(.fractionLength(1))))° · DP \(s.dewPoint.formatted(.number.precision(.fractionLength(1))))° · h \(s.enthalpy.formatted(.number.precision(.fractionLength(1))))")
                .font(DS.number(11)).foregroundColor(DS.ink2)
        }
        .padding(13).frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.card)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(DS.border, lineWidth: 1))
        .overlay(Rectangle().frame(width: 4).foregroundColor(accent), alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct MixedCard: View {
    var a: PsychroState, cfmA: Double, b: PsychroState, cfmB: Double, altitude: Altitude
    var body: some View {
        let m = Psychrometrics.mix(a, cfmA: cfmA, b, cfmB: cfmB, altitude: altitude)
        VStack(alignment: .leading, spacing: 5) {
            HStack { Text("M — Mixed").font(DS.ui(13, .bold)).foregroundColor(.white)
                Spacer(); Text("25% OA").font(DS.number(11)).foregroundColor(Color(hex: 0x8FB0C8)) }
            Text("\(m.dryBulb.formatted(.number.precision(.fractionLength(1))))°")
                .font(DS.number(22)).foregroundColor(.white)
        }
        .padding(13).frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.ink).clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
