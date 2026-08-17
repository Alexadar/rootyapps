import SwiftUI
import AirsideKit
import AirsideUI

/// Duct — straight duct from friction, with the velocity check that separates a
/// working system from a whistling one. States: empty / mid-entry / computed / out-of-range
/// all fall out of the live result.
struct DuctView: View {
    @State private var cfm = 850.0
    @State private var friction = 0.08
    @State private var altitude = Altitude.denver

    private var result: DuctSizing.Result { DuctSizing.size(cfm: cfm, frictionPer100ft: friction) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Duct").font(DS.ui(21, .bold)).foregroundColor(DS.ink)
                Spacer()
                AltitudeChip(altitude: altitude) {}
            }.padding(.horizontal, DS.s4).padding(.top, DS.s2)
            Text("Straight duct from friction — velocity check.")
                .font(DS.ui(11, .medium)).foregroundColor(DS.ink2)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, DS.s4)

            VStack(spacing: 11) {
                VStack(spacing: 2) {
                    Text("Round diameter").font(DS.ui(10.5, .semibold)).foregroundColor(DS.ink2)
                    NumberReadout(result.diameterIn.formatted(.number.precision(.fractionLength(1))), unit: "″", size: 44)
                    Text("≈ \(result.equivRect.a)″×\(result.equivRect.b)″ rectangular")
                        .font(DS.number(11)).foregroundColor(DS.ink2)
                }
                .frame(maxWidth: .infinity).padding(14)
                .background(DS.card)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(result.whistles ? DS.warn : DS.border, lineWidth: result.whistles ? 1.5 : 1))
                .clipShape(RoundedRectangle(cornerRadius: 14))

                if result.whistles {
                    StatusBanner(kind: .warn, title: "Velocity \(Int(result.velocityFPM).formatted()) FPM — will whistle",
                                 detail: "above 1,200 FPM — lower friction or size up")
                } else {
                    StatusBanner(kind: .ok, title: "Velocity \(Int(result.velocityFPM).formatted()) FPM — quiet",
                                 detail: "below 1,200 FPM noise limit")
                }
            }.padding(DS.s4)

            Spacer()

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    StepperField(title: "CFM", value: $cfm, unit: "", step: 25, active: true)
                    StepperField(title: "Friction /100ft", value: $friction, unit: "", step: 0.01, active: false)
                }
            }
            .padding(DS.s4)
            .background(DS.panel)
            .overlay(Rectangle().frame(height: 1).foregroundColor(DS.border), alignment: .top)
        }
        .background(DS.breeze.ignoresSafeArea())
    }
}
