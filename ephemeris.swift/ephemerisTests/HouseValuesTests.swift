import Testing
import Foundation
import EphemerisKit
@testable import Ephemeris

/// Houses at the ViewModel layer — the values the Chart tab actually renders, plus the
/// location/system persistence the Moment card depends on.
@Suite("House values")
@MainActor
struct HouseValuesTests {

    private static let kyiv = GeoLocation(latitude: 50.45, longitude: 30.52, name: "Kyiv")
    private static let svalbard = GeoLocation(latitude: 78.22, longitude: 15.65, name: "Longyearbyen")

    /// A view model pinned to an absolute moment (device zone ⇒ `instant` is the identity on
    /// `date`, so assertions are machine-independent — same trick as `PositionValuesTests`).
    private func vm(at t: Date, at place: GeoLocation?, system: HouseSystem = .placidus) -> ChartViewModel {
        let vm = ChartViewModel()
        vm.timeZone = .current
        vm.houseSystem = system
        vm.location = place
        vm.date = t
        vm.recompute()
        return vm
    }

    @Test func noPlaceMeansNoHouses() {
        let v = vm(at: utc(2026, 6, 21, 12, 0), at: nil)
        #expect(v.houses == nil)
        #expect(v.houseFallback == nil)
        #expect(!v.positions.isEmpty)      // the rest of the chart still works
    }

    @Test func settingAPlaceProducesTwelveCusps() {
        let v = vm(at: utc(2026, 6, 21, 12, 0), at: Self.kyiv)
        let h = try! #require(v.houses)
        #expect(h.cusps.count == 12)
        #expect(h.system == .placidus)
        // Cusp 1 is the Ascendant, cusp 10 the Midheaven (quadrant system).
        #expect(abs(AstroMath.norm180(h.cusp(1) - h.angles.ascendant)) < 1e-9)
        #expect(abs(AstroMath.norm180(h.cusp(10) - h.angles.midheaven)) < 1e-9)
    }

    /// The ViewModel must agree exactly with the Kit — the numbers on screen are the numbers
    /// the engine computed, with no drift through `instant`.
    @Test func viewModelMatchesTheEngineDirectly() {
        let t = utc(2026, 6, 21, 12, 0)
        let v = vm(at: t, at: Self.kyiv, system: .regiomontanus)
        let direct = Houses.compute(at: t, location: Self.kyiv, system: .regiomontanus)!
        for n in 1...12 {
            #expect(abs(AstroMath.norm180(v.houses!.cusp(n) - direct.cusp(n))) < 1e-9, "cusp \(n)")
        }
    }

    /// Every rendered cusp's sign label must match its longitude, and the formatted
    /// "d° mm′" string must round-trip — these are exactly what `HousesCard` shows.
    @Test func renderedCuspFieldsAreConsistent() {
        for system in HouseSystem.allCases {
            let v = vm(at: utc(2026, 3, 15, 0, 0), at: Self.kyiv, system: system)
            let h = try! #require(v.houses)
            for n in 1...12 {
                let lon = h.cusp(n)
                #expect(h.sign(ofCusp: n) == ZodiacSign.from(longitude: lon))
                let parsed = Self.parseDegMin(HousesCard.degMin(lon))
                let within = AstroMath.norm360(lon).truncatingRemainder(dividingBy: 30)
                #expect(abs(parsed - within) < 1.0 / 60 + 1e-6, "\(system) cusp \(n)")
            }
        }
    }

    /// Beyond the polar circle the chosen system can't be computed; the app must fall back to
    /// Whole Sign and say which system it dropped, rather than showing nothing.
    @Test func polarLatitudeFallsBackToWholeSign() {
        let v = vm(at: utc(2026, 6, 21, 12, 0), at: Self.svalbard, system: .placidus)
        let h = try! #require(v.houses)
        #expect(h.system == .wholeSign)
        #expect(v.houseFallback == .placidus)
        // Whole Sign is still well formed up there.
        for n in 1...12 {
            #expect(h.cusp(n).truncatingRemainder(dividingBy: 30) < 1e-9)
        }
    }

    @Test func temperateLatitudeNeedsNoFallback() {
        for system in HouseSystem.allCases {
            let v = vm(at: utc(2026, 6, 21, 12, 0), at: Self.kyiv, system: system)
            #expect(v.houseFallback == nil, "\(system) should not need a fallback at 50°N")
            #expect(v.houses?.system == system)
        }
    }

    /// Houses recompute on the cheap path, so they stay in step while the date is scrubbed.
    @Test func housesFollowTheDate() {
        let v = vm(at: utc(2026, 6, 21, 12, 0), at: Self.kyiv)
        let before = v.houses!.angles.ascendant
        v.date = v.date.addingTimeInterval(3 * 3600)   // the sky turns ~45°
        let after = v.houses!.angles.ascendant
        #expect(abs(AstroMath.norm180(after - before)) > 1)
    }

    /// Location and house system survive a relaunch (same pattern as the time-zone test).
    @Test func locationAndSystemPersistAcrossViewModels() {
        let keys = ["observerLatitude", "observerLongitude", "observerPlaceName", "houseSystem"]
        keys.forEach(UserDefaults.standard.removeObject(forKey:))
        defer { keys.forEach(UserDefaults.standard.removeObject(forKey:)) }

        let first = ChartViewModel()
        first.location = Self.kyiv
        first.houseSystem = .campanus

        let second = ChartViewModel()          // init() reads the saved values back
        #expect(second.location?.name == "Kyiv")
        #expect(abs((second.location?.latitude ?? 0) - 50.45) < 1e-9)
        #expect(abs((second.location?.longitude ?? 0) - 30.52) < 1e-9)
        #expect(second.houseSystem == .campanus)
    }

    @Test func clearingThePlaceRemovesTheHouses() {
        let keys = ["observerLatitude", "observerLongitude", "observerPlaceName"]
        defer { keys.forEach(UserDefaults.standard.removeObject(forKey:)) }
        let v = vm(at: utc(2026, 6, 21, 12, 0), at: Self.kyiv)
        #expect(v.houses != nil)
        v.location = nil
        #expect(v.houses == nil)
        #expect(UserDefaults.standard.object(forKey: "observerLatitude") == nil)
    }

    private static func parseDegMin(_ s: String) -> Double {
        let parts = s.replacingOccurrences(of: "′", with: "")
                     .replacingOccurrences(of: "°", with: "")
                     .split(separator: " ")
        let d = Double(parts[0]) ?? 0, m = Double(parts.count > 1 ? parts[1] : "0") ?? 0
        return d + m / 60
    }
}
