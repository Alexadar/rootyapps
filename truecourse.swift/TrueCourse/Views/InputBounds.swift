import Foundation

/// Oracle-backed input domains for every calculator field — the single source of truth for
/// each `NumberField(range:)`. Ranges are forgiving-but-realistic GA bounds (student light
/// singles → light jets) so a student can never enter nonsense. Each carries a cited source,
/// the same discipline the `*Kit` math uses.
///
/// Sources spot-checked against Sporty's E6B / ForeFlight field UIs (2026-07).
enum Bounds {
    // Oracle = compass rose is 360°; wind direction entered as true. FAA-H-8083-25 PHAK,
    // "Navigation". https://www.faa.gov/regulations_policies/handbooks_manuals/aviation/phak
    static let bearingDeg: ClosedRange<Double> = 0...360

    // Oracle = GA singles (~40 kt stall) through light jets (~500 KTAS). Regulatory note:
    // no aircraft may exceed 250 KIAS below 10,000 ft MSL — 14 CFR 91.117(a).
    // https://www.ecfr.gov/current/title-14/part-91/section-91.117
    static let airspeedKt: ClosedRange<Double> = 0...500

    // Oracle = surface/enroute winds; upper-level jet cores can exceed 150–200 kt (PHAK).
    // 250 kt is a forgiving UI cap.
    static let windSpeedKt: ClosedRange<Double> = 0...250

    // Oracle = sub-sea-level fields (Death Valley ≈ −282 ft) to high altitude. NOTE the ISA
    // standard-atmosphere (density-alt / TAS) model is only valid to the tropopause at
    // 36,089 ft; above that the lapse goes isothermal.
    // https://en.wikipedia.org/wiki/International_Standard_Atmosphere
    static let altitudeFt: ClosedRange<Double> = -1500...60000

    // Height to lose / AGL height — non-negative subset of the altitude domain.
    static let heightFt: ClosedRange<Double> = 0...60000

    // Oracle = sensitive-altimeter Kollsman window range 948–1050 hPa = 28.00–31.00 inHg;
    // the instrument physically cannot be set beyond it. FAA Instrument Flying Handbook.
    // https://www.faa.gov/regulations_policies/handbooks_manuals/aviation/instrument_flying_handbook
    static let altimeterInHg: ClosedRange<Double> = 28.00...31.00

    // Oracle = real atmospheric extremes (records ≈ −89 °C … +57 °C); ISA sea-level datum 15 °C.
    // https://en.wikipedia.org/wiki/International_Standard_Atmosphere
    static let temperatureC: ClosedRange<Double> = -60...55

    // Field elevation (MSL) — sub-sea-level to a high plateau.
    static let elevationFt: ClosedRange<Double> = -1500...30000

    static let distanceNm: ClosedRange<Double> = 0...10000
    static let groundspeedKt: ClosedRange<Double> = 0...600
    static let timeMin: ClosedRange<Double> = 0...1440   // ≤ 24 h planning window
    static let timeHr: ClosedRange<Double> = 0...24

    static let fuelGph: ClosedRange<Double> = 0...500    // singles ~5–20; light jets 150–300+
    static let fuelGal: ClosedRange<Double> = 0...5000

    // Oracle = FAA departure-procedure climb gradients rarely exceed ~500–800 ft/nm.
    // AIM 5-2-9. https://www.faa.gov/air_traffic/publications/atpubs/aim_html
    static let climbGradientFtPerNm: ClosedRange<Double> = 0...1000

    // Oracle = light singles ≈ 9:1; high-performance sailplanes up to ~60–70:1.
    static let glideRatio: ClosedRange<Double> = 1...70

    // Weight & Balance — typical light-single per-station load & datum arms.
    // FAA-H-8083-1 Aircraft Weight & Balance Handbook.
    static let stationWeightLb: ClosedRange<Double> = 0...1000
    static let armIn: ClosedRange<Double> = 0...200

    static let durationMin: ClosedRange<Double> = 0...600   // count-down timer
}
