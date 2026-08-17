import Testing
import Foundation
@testable import EphemerisKit

/// What a saved chart *computes*, as opposed to what it stores.
///
/// `ChartStoreTests` proves a chart survives being written and read. These prove the numbers on it
/// are right — the layer that was missing while natal was the app's headline feature and its least
/// tested part.
///
/// Fixture: **1990-03-15 14:30 UTC, Berlin (52.52 N, 13.405 E)**. Expected values are transcribed
/// from the Kit itself and duplicated here on purpose (§C.1): if a Kit answer changes, both layers
/// must be updated and the diff makes that visible.
@Suite("Natal chart")
struct NatalChartTests {

    private static let birth = ISO8601DateFormatter().date(from: "1990-03-15T14:30:00Z")!

    private func fixture(timeKnown: Bool = true) -> SavedChart {
        SavedChart(name: "Fixture",
                   birthInstant: Self.birth,
                   timeZoneID: "Europe/Berlin",
                   isTimeKnown: timeKnown,
                   latitude: 52.52, longitude: 13.405, placeName: "Berlin")
    }

    /// "d° mm′" within the sign — the same reading a user gets.
    private func degMin(_ lon: Double) -> String {
        let within = AstroMath.norm360(lon).truncatingRemainder(dividingBy: 30)
        let total = Int((within * 60).rounded())
        return "\(total / 60)° \(String(format: "%02d", total % 60))′"
    }

    // MARK: - Positions

    @Test func natalPositionsAreWhereTheKitSaysTheyAre() {
        let c = fixture()
        func body(_ b: CelestialBody) -> BodyPosition {
            c.positions.first { $0.body == b }!
        }

        #expect(degMin(body(.sun).longitude) == "24° 45′")
        #expect(body(.sun).sign == .pisces)
        #expect(degMin(body(.moon).longitude) == "10° 59′")
        #expect(body(.moon).sign == .scorpio)
        #expect(degMin(body(.saturn).longitude) == "23° 19′")
        #expect(body(.saturn).sign == .capricorn)
        #expect(abs(body(.saturn).longitude - 293.3202) < 0.01)
    }

    /// Both polarities, so a retrograde flag stuck on or off cannot pass.
    @Test func retrogradeReflectsTheEphemeris() {
        let c = fixture()
        #expect(c.positions.first { $0.body == .pluto }?.retrograde == true)
        #expect(c.positions.first { $0.body == .sun }?.retrograde == false)
    }

    // MARK: - Aspects and angles

    @Test func natalAspectsMatchTheKit() {
        let c = fixture()
        #expect(c.aspects.count == 12)

        let sunSaturn = c.aspects.first { $0.a == .sun && $0.b == .saturn }
        #expect(sunSaturn?.type.name == "Sextile")
        #expect(abs((sunSaturn?.orb ?? 0) - 1.43) < 0.01)

        // Sorted by exactness, so the tightest is first — the property the wheel and the
        // "Tightest aspects" card both rely on.
        #expect(c.aspects.first?.orb ?? 1 <= c.aspects.last?.orb ?? 0)
    }

    @Test func anglesRequireABirthTimeAndOtherwiseCompute() {
        let timed = fixture()
        let h = try! #require(timed.houses(system: .placidus))
        #expect(degMin(h.angles.ascendant) == "28° 00′")
        #expect(degMin(h.angles.midheaven) == "16° 18′")

        // Unknown time: absent, never computed from an assumed noon.
        #expect(fixture(timeKnown: false).houses(system: .placidus) == nil)
        #expect(!fixture(timeKnown: false).positions.isEmpty,
                "positions stay valid without a birth time")
    }

    // MARK: - Transits

    /// ⚠ The one that matters, and the one a naive test gets wrong.
    ///
    /// A Saturn return is transiting Saturn arriving back on natal Saturn — a body aspecting
    /// *itself* across two sets. `Aspects.detect(in:)` skips self-pairs by construction, so if
    /// `detect(between:and:)` had inherited that guard the single most recognisable transit in
    /// astrology would silently not exist.
    ///
    /// The instant comes from `Returns` rather than from arithmetic: this chart's first Saturn
    /// return is at **age 29.842**, not the 29.457-year mean period. Asking at the mean finds
    /// nothing, because a geocentric passage over a fixed degree is displaced by the retrograde
    /// loop. Two modules agreeing here is the real assertion.
    @Test func saturnReturnAppearsAsATransitOfSaturnOnNatalSaturn() throws {
        let c = fixture()
        let cycle = try #require(Returns.saturnReturn(natal: Self.birth, ordinal: 1))
        let at = cycle.first.date

        let selfPairs = c.transits(at: at, orbFactor: 1.0)
            .filter { $0.moving == .saturn && $0.reference == .saturn }

        #expect(selfPairs.count == 1, "the Saturn return must be reported, not skipped as a self-pair")
        #expect(selfPairs.first?.type.name == "Conjunction")
        #expect((selfPairs.first?.orb ?? 99) < 0.01, "at the return instant the orb is essentially zero")
        #expect(selfPairs.first?.isSelfPair == true)

        let years = at.timeIntervalSince(Self.birth) / (365.2422 * 86_400)
        #expect(years > 28.0 && years < 30.5, "a first Saturn return lands in the high twenties")
    }

    /// `moving` is the transiting body, `reference` is the natal one. Getting these the wrong way
    /// round reads plausibly and inverts every interpretation.
    @Test func transitsNameWhichSideIsNatal() {
        let c = fixture()
        let at = ISO8601DateFormatter().date(from: "2026-07-15T12:00:00Z")!
        let transits = c.transits(at: at, orbFactor: 1.0)
        #expect(!transits.isEmpty)

        let natalLongitudes = Dictionary(uniqueKeysWithValues:
            c.positions.map { ($0.body, $0.longitude) })
        for t in transits {
            let natal = try! #require(natalLongitudes[t.reference])
            let moving = Ephemeris.longitude(of: t.moving, at: at)
            let separation = AstroMath.separation(moving, natal)
            #expect(abs(separation - t.type.angle) <= t.type.baseOrb + 0.001,
                    "\(t.moving.rawValue)→\(t.reference.rawValue) is not actually in orb")
        }
    }

    // MARK: - Synastry

    @Test func synastryIsSymmetricApartFromWhichSideIsWhich() {
        let a = fixture()
        let b = SavedChart(name: "Other",
                           birthInstant: ISO8601DateFormatter().date(from: "1975-07-04T09:15:00Z")!,
                           timeZoneID: "America/Los_Angeles",
                           latitude: 34.052, longitude: -118.244, placeName: "Los Angeles")

        let ab = a.synastry(with: b)
        let ba = b.synastry(with: a)
        #expect(ab.count == ba.count, "the same pairs are in orb whichever way round it is asked")

        // Every pair in one direction appears mirrored in the other, with the same orb.
        for x in ab {
            let mirror = ba.first { $0.moving == x.reference && $0.reference == x.moving }
            let found = try! #require(mirror)
            #expect(abs(found.orb - x.orb) < 1e-9)
            #expect(found.type.name == x.type.name)
        }
    }
}
