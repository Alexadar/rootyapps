import SwiftUI
import AirsideKit
import AirsideUI

/// Psychrometrics — chart as a live view onto numeric entry. Inputs sit low for
/// one-handed reach; typing moves the point, dragging the point updates the numbers.
struct PsychrometricsView: View {
    @State private var db = 75.0
    @State private var rh = 50.0
    @State private var altitude = Altitude.denver
    @State private var unit: UnitSystem = .ip
    @State private var showAltSheet = false

    private var state: PsychroState { Psychrometrics.solve(dryBulbF: db, relHumidityPercent: rh, altitude: altitude) }
    private var si: Bool { unit == .si }
    private func f(_ v: Double, _ d: Int) -> String { v.formatted(.number.precision(.fractionLength(d))) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Psychrometrics").font(DS.ui(21, .bold)).foregroundColor(DS.ink)
                Spacer()
                AltitudeChip(altitude: altitude) { showAltSheet = true }
                UnitToggle(system: $unit)
            }.padding(.horizontal, DS.s4).padding(.top, DS.s2)

            PsychroChart(dryBulb: $db, relHumidity: $rh, altitude: altitude)
                .frame(height: 168).padding(DS.s3)

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 7) {
                    ResultTile(label: "Wet bulb", value: f(si ? Temp.fToC(state.wetBulb) : state.wetBulb, 1), unit: si ? "°C" : "°F")
                    ResultTile(label: "Dew point", value: f(si ? Temp.fToC(state.dewPoint) : state.dewPoint, 1), unit: si ? "°C" : "°F")
                    ResultTile(label: "Humidity ratio", value: si ? f(Convert.grToGkg(state.humidityRatio), 2) : f(state.humidityRatio, 1), unit: si ? "g/kg" : "gr/lb")
                    ResultTile(label: "Enthalpy", value: si ? f(Convert.btuLbToKjKg(state.enthalpy), 1) : f(state.enthalpy, 1), unit: si ? "kJ/kg" : "Btu/lb")
                    ResultTile(label: "Specific vol.", value: si ? f(Convert.ft3LbToM3Kg(state.specificVolume), 3) : f(state.specificVolume, 2), unit: si ? "m³/kg" : "ft³/lb")
                    ResultTile(label: "Deg. saturation", value: f(state.degreeOfSaturation, 1), unit: "%")
                }.padding(.horizontal, DS.s4)
            }

            // Inputs — low, thumb-reachable.
            VStack(alignment: .leading, spacing: 7) {
                Text("KNOWN — ANY TWO").font(DS.ui(10, .semibold)).foregroundColor(DS.ink2).tracking(1)
                HStack(spacing: 10) {
                    StepperField(title: "Dry bulb", value: $db, unit: si ? "°C" : "°F", step: 0.5, active: true)
                    StepperField(title: "Rel. humidity", value: $rh, unit: "%", step: 1, active: false)
                }
            }
            .padding(DS.s4)
            .background(DS.panel)
            .overlay(Rectangle().frame(height: 1).foregroundColor(DS.border), alignment: .top)
        }
        .background(DS.breeze.ignoresSafeArea())
        .sheet(isPresented: $showAltSheet) { AltitudeSheet(altitude: $altitude) }
    }
}

struct StepperField: View {
    var title: String
    @Binding var value: Double
    var unit: String, step: Double, active: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(DS.ui(11, .semibold)).foregroundColor(active ? DS.water : DS.ink2)
            NumberReadout(value.formatted(.number.precision(.fractionLength(1))), unit: unit, size: 26)
            HStack(spacing: 7) {
                stepButton("minus") { value -= step }
                stepButton("plus") { value += step }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(DS.card)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(active ? DS.water : DS.border, lineWidth: active ? 2 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
    func stepButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundColor(DS.water)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(Color(hex: 0xEEF4FB))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color(hex: 0xCBDDF1), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain)
    }
}

struct AltitudeSheet: View {
    @Binding var altitude: Altitude
    @Environment(\.dismiss) private var dismiss
    private let presets: [(String, Altitude)] = [("Sea level", .seaLevel), ("Denver 5,280", .denver), ("Mexico City 7,350", .mexicoCity)]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Site elevation", systemImage: "triangle").font(DS.ui(18, .bold)).foregroundColor(DS.ink)
            Text("Every constant on every screen corrects to this.").font(DS.ui(11.5)).foregroundColor(DS.ink2)
            NumberReadout("\(Int(altitude.feet).formatted())", unit: "ft", size: 36)
                .frame(maxWidth: .infinity).padding(10)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.water, lineWidth: 2))
            HStack {
                ForEach(presets, id: \.0) { p in
                    Button { altitude = p.1 } label: {
                        Text(p.0).font(DS.number(12))
                            .foregroundColor(altitude == p.1 ? .white : DS.ink2)
                            .padding(.horizontal, 13).padding(.vertical, 8)
                            .background(altitude == p.1 ? DS.water : DS.panel).clipShape(Capsule())
                    }.buttonStyle(.plain)
                }
            }
            StatusBanner(kind: .ok, title: "Sensible constant here is \(altitude.sensibleConstant.formatted(.number.precision(.fractionLength(2))))",
                         detail: "sea-level value is 1.08")
            Button { dismiss() } label: {
                Text("Apply to all tools").font(DS.ui(15, .semibold)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 13).background(DS.water)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }.buttonStyle(.plain)
        }
        .padding(20).presentationDetents([.medium])
        .background(DS.breeze)
    }
}
