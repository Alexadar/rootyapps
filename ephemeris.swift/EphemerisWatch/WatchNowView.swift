import SwiftUI
import EphemerisKit

/// The glanceable screen: what is true right now, in the order someone actually asks it.
///
/// Retrogrades first — it is the single most-checked fact in this domain — then the Moon, then
/// the rising sign, then what is coming. Everything here except the Ascendant is a pure function
/// of the date, so this screen still works fully when no place has been set; only the AC row
/// degrades, and it says so rather than guessing.
struct WatchNowView: View {
    let date: Date
    let positions: [BodyPosition]
    let houses: HouseCusps?
    let hasPlace: Bool

    private var retrogrades: [BodyPosition] { positions.filter(\.retrograde) }

    /// Sun–Moon elongation drives both: 0° new, 180° full, and waxing while the Moon leads the
    /// Sun by less than half a turn.
    static func illumination(at date: Date) -> Double {
        let e = elongation(at: date)
        return (1 - cos(e * .pi / 180)) / 2
    }
    static func waxing(at date: Date) -> Bool { elongation(at: date) < 180 }
    static func elongation(at date: Date) -> Double {
        AstroMath.norm360(Ephemeris.longitude(of: .moon, at: date)
                          - Ephemeris.longitude(of: .sun, at: date))
    }
    private var moon: BodyPosition? { positions.first { $0.body == .moon } }

    var body: some View {
        List {
            Section {
                if retrogrades.isEmpty {
                    Text(L.loc("Nothing retrograde")).font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    // Glyphs, not names: the audience reads symbols faster, and ten names would
                    // not fit anyway.
                    HStack(spacing: 6) {
                        ForEach(retrogrades) { p in
                            Text(verbatim: p.body.glyph + "\u{FE0E}").foregroundStyle(.orange)
                        }
                        Text(verbatim: "℞").foregroundStyle(.orange).font(.caption)
                    }
                }
            } header: { Text(L.loc("Retrograde")) }





            if let moon {
                Section {
                    // Text, not a drawn disc. The phase shape never rendered correctly on device
                    // and a wrong moon is worse than no moon — the number is unambiguous.
                    LabeledRow(glyph: moon.body.glyph,
                               label: L.loc(ZodiacSign.from(longitude: moon.longitude).name),
                               value: "\(Int(Self.illumination(at: date) * 100))%")
                } header: { Text(L.loc("Moon")) }
            }

            Section {
                if let houses, hasPlace {
                    LabeledRow(glyph: ZodiacSign.from(longitude: houses.angles.ascendant).glyph,
                               label: L.loc(ZodiacSign.from(longitude: houses.angles.ascendant).name),
                               value: Format.degMin(houses.angles.ascendant))
                } else {
                    // The Ascendant needs an observer. Saying so is more useful than a guess that
                    // looks right and is not.
                    Text(L.loc("Set a place on iPhone")).font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } header: { Text(L.loc("Rising")) }
        }
        // Without this the List paints its own dark background and the sky is only visible in
        // the margins. Row backgrounds go too, so the cards read as glass over the stars.
        .scrollContentBackground(.hidden)
    }
}

/// Shared row shape so the three sections line up rather than each inventing its own spacing.
struct LabeledRow: View {
    let glyph: String
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: glyph + "\u{FE0E}")
            Text(label).font(.caption)
            Spacer()
            Text(verbatim: value).font(.caption).monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

/// Degree formatting, shared by every watch screen so "12° 04′" cannot drift between them.
enum Format {
    static func degMin(_ longitude: Double) -> String {
        let within = AstroMath.norm360(longitude).truncatingRemainder(dividingBy: 30)
        let d = Int(within), m = Int((within - Double(d)) * 60)
        return String(format: "%d° %02d′", d, m)
    }
}
