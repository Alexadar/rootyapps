import SwiftUI
import EphemerisKit

/// The twelve house cusps and the four angles, with a picker for the dividing system.
/// Shown only once a place is set — houses are undefined without one.
struct HousesCard: View {
    @ObservedObject var vm: ChartViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Houses", trailing: vm.houses.map { Text(L.loc($0.system.displayName)) })

            if let houses = vm.houses {
                systemPicker
                if let attempted = vm.houseFallback { fallbackNote(attempted) }
                angles(houses.angles)
                NebulaPalette.divider.frame(height: 0.75)
                ForEach(1...12, id: \.self) { n in
                    cuspRow(n, houses)
                    if n < 12 { NebulaPalette.divider.frame(height: 0.75) }
                }
            } else {
                systemPicker
                Text("Set a place in the Moment card to see the Ascendant, Midheaven and houses.")
                    .font(.callout)
                    .foregroundStyle(NebulaPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .glassCard()
    }

    private var systemPicker: some View {
        Picker("House system", selection: $vm.houseSystem) {
            ForEach(HouseSystem.allCases) { Text(L.loc($0.displayName)).tag($0) }
        }
        .pickerStyle(.menu)
        .labelsHidden()
    }

    /// Placidus/Koch are undefined beyond the polar circle — say so instead of showing nothing.
    private func fallbackNote(_ attempted: HouseSystem) -> some View {
        Text("\(Text(L.loc(attempted.displayName))) is undefined this far from the equator — showing Whole Sign.")
            .font(.caption)
            .foregroundStyle(NebulaPalette.retrograde)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func angles(_ a: ChartAngles) -> some View {
        HStack(spacing: 18) {
            angle("AC", a.ascendant)
            angle("MC", a.midheaven)
            Spacer()
        }
    }

    private func angle(_ label: String, _ lon: Double) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(NebulaPalette.accent)
            SignChip(glyph: ZodiacSign.from(longitude: lon).glyph, size: 18)
            Text(Self.degMin(lon)).monospacedDigit().font(.callout)
        }
    }

    private func cuspRow(_ n: Int, _ houses: HouseCusps) -> some View {
        let lon = houses.cusp(n)
        return HStack(spacing: 10) {
            Text(n, format: .number)
                .font(.callout.weight(.semibold)).monospacedDigit()
                .foregroundStyle(isAngular(n) ? NebulaPalette.accent : NebulaPalette.textSecondary)
                .frame(width: 22, alignment: .trailing)
            SignChip(glyph: ZodiacSign.from(longitude: lon).glyph)
            Text(Self.degMin(lon)).monospacedDigit()
            Spacer()
            Text(L.loc(ZodiacSign.from(longitude: lon).name))
                .foregroundStyle(NebulaPalette.textSecondary)
        }
        .font(.callout)
    }

    /// Houses 1/4/7/10 are the angular ones — worth picking out.
    private func isAngular(_ n: Int) -> Bool { n == 1 || n == 4 || n == 7 || n == 10 }

    /// "d° mm′" within the sign, matching `BodyPosition.degMinString`.
    static func degMin(_ longitude: Double) -> String {
        let within = AstroMath.norm360(longitude).truncatingRemainder(dividingBy: 30)
        let total = Int((within * 60).rounded())
        var d = total / 60
        let m = total % 60
        if d >= 30 { d -= 30 }
        return "\(d)° \(String(format: "%02d", m))′"
    }
}
