import SwiftUI
import AltitudeKit
import HeatKit
import PsychroKit
import UnitsKit

/// Where altitude lives.
///
/// The chip that opens this sheet is in every tool's toolbar, and this sheet says what the
/// elevation *does* — it shows the sensible constant at this site next to the 1.08 the trade
/// quotes, so the correction is a number the user can see rather than a claim in a settings pane.
///
/// The constant shown is computed by ``AirSideHeat`` from the air at this elevation, not looked up:
/// the figure on this screen and the figure behind every load calculation are the same call.
struct ElevationSheet: View {

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    private struct Preset: Identifiable {
        let name: LocalizedStringKey
        let spokenName: String
        let metres: Double
        var id: String { spokenName }
    }

    private let presets: [Preset] = [
        .init(name: "Sea level", spokenName: "Sea level", metres: 0),
        .init(name: "Denver", spokenName: "Denver", metres: 5280 * 0.3048),
        .init(name: "Mexico City", spokenName: "Mexico City", metres: 7350 * 0.3048),
    ]

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.s4) {
                    Text("Every constant in every tool is corrected to this elevation.")
                        .font(DS.ui(12.5))
                        .foregroundStyle(DS.ink2)

                    NumericField(title: "Site elevation",
                                 spokenTitle: "Site elevation",
                                 quantity: .elevation,
                                 system: settings.unitSystem,
                                 siValue: $settings.elevationMetres,
                                 step: settings.unitSystem == .ip ? 100 : 50,
                                 isActive: true,
                                 identifier: "elevation.field")

                    HStack(spacing: DS.s2) {
                        ForEach(presets) { preset in
                            presetButton(preset, selected: settings.elevationMetres == preset.metres)
                        }
                    }

                    constantsPanel

                    Text("This is the standard atmosphere for the elevation, not today's weather. "
                         + "A barometer reading corrected to sea level is a different number and "
                         + "does not belong here.")
                        .font(DS.ui(11.5))
                        .foregroundStyle(DS.ink2)
                }
                .padding(DS.s4)
            }
            .background(DS.breeze)
            .navigationTitle("Elevation")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("elevation.done")
                }
            }
        }
    }

    private func presetButton(_ preset: Preset, selected: Bool) -> some View {
        Button {
            settings.elevationMetres = preset.metres
        } label: {
            Text(preset.name)
                .font(DS.ui(12.5, .medium))
                .foregroundStyle(selected ? Color.white : DS.ink)
                .padding(.horizontal, DS.s3)
                .padding(.vertical, DS.s2)
                .frame(maxWidth: .infinity, minHeight: DS.hitTarget - 12)
                .background(selected ? DS.water : DS.panel)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(preset.spokenName)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier("elevation.preset.\(preset.spokenName)")
    }

    /// What the elevation actually costs, in the numbers the trade quotes.
    private var constantsPanel: some View {
        VStack(alignment: .leading, spacing: DS.s2) {
            LabeledContent {
                Text(Fmt.valueWithUnit(si: settings.pressure, .barometricPressure,
                                       settings.unitSystem))
                    .font(DS.number(14))
            } label: {
                Text("Barometric pressure").font(DS.ui(12.5))
            }

            if let ratio = sensibleConstantRatio {
                StatusBanner(
                    kind: abs(ratio - 1) < 0.02 ? .ok : .warning,
                    title: "Sensible constant here is \(Fmt.number(ratio * 1.08, decimals: 3))",
                    detail: "The trade's 1.08 is a sea-level number. At this elevation it is "
                          + "\(Fmt.number((1 - ratio) * 100, decimals: 1)) % low.")
                .accessibilityIdentifier("elevation.constantBanner")
            }
        }
        .padding(DS.s3)
        .background(DS.card)
        .overlay(RoundedRectangle(cornerRadius: DS.radiusCard).stroke(DS.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusCard))
    }

    /// The site's sensible constant as a fraction of the sea-level one, both computed by HeatKit
    /// from dry air at 20 °C so that the only difference between them is the elevation.
    private var sensibleConstantRatio: Double? {
        func constant(at pressure: Double) -> Double? {
            guard let air = try? MoistAir(dryBulb: 20, relativeHumidity: 0, pressure: pressure)
            else { return nil }
            return try? AirSideHeat.sensibleConstantPerVolumeFlow(
                specificVolume: air.specificVolume, humidityRatio: 0)
        }
        guard let here = constant(at: settings.pressure),
              let sea = constant(at: Elevation.seaLevelPressure), sea > 0 else { return nil }
        return here / sea
    }
}
