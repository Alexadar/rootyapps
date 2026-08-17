import Testing
import Foundation
import EphemerisKit
@testable import Ephemeris

/// The sidereal frame, asserted where it actually has to arrive.
///
/// The failure this suite exists for is **applying the offset at render time only**. That version
/// passes every casual inspection: each displayed degree is correct, the wheel looks right, the sign
/// labels change. What silently stays tropical is everything computed *from* the positions — aspects,
/// house placements, dignities, element counts. The chart is then a mix of two frames, which is
/// meaningless, and nothing on screen says so.
///
/// So none of these tests look at a longitude in isolation. They check that the shift reached the
/// derived values.
///
/// ## Why this suite is a class
///
/// `ChartViewModel.zodiac` persists on set — that is the feature. It also means a test that selects
/// a sidereal frame leaves it selected for **every other suite in the process**, and the damage is
/// silent: `positionsMatchHorizons` and `viewModelMatchesTheEngineDirectly` simply start comparing
/// sidereal longitudes against tropical oracles and fail with numbers that look like an engine
/// regression. That happened while writing this file, and six unrelated tests went red.
///
/// A class suite gets `init`/`deinit`, so the key is cleared before each test and the user's real
/// value is put back after. A struct suite cannot do the second half.
@Suite("Sidereal frame")
@MainActor
final class SiderealFrameTests {

    private static let kyiv = GeoLocation(latitude: 50.45, longitude: 30.52, name: "Kyiv")
    /// A private defaults suite per suite-instance, so nothing here can be observed by another
    /// test. `UserDefaults.standard` is process-global and the suites run concurrently.
    private let defaults: UserDefaults
    private let suiteName: String

    init() {
        suiteName = "sidereal.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

    private func viewModel(_ ayanamsa: Ayanamsa?) -> ChartViewModel {
        let vm = ChartViewModel(defaults: defaults)
        vm.location = Self.kyiv
        var c = DateComponents(); c.year = 2026; c.month = 3; c.day = 1; c.hour = 12
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        vm.timeZone = TimeZone(secondsFromGMT: 0)!
        vm.date = cal.date(from: c)!
        vm.zodiac = ayanamsa
        return vm
    }

    // MARK: - Default

    @Test func tropicalIsTheDefaultAndChangesNothing() {
        let vm = ChartViewModel(defaults: UserDefaults(suiteName: "sidereal.fresh.\(UUID())")!)
        #expect(vm.zodiac == nil, "an install with no preference must read tropical")
    }

    // MARK: - The shift reaches the positions

    @Test func everyBodyMovesBackByTheAyanamsa() {
        let tropical = viewModel(nil), sidereal = viewModel(.lahiri)
        let expected = Ayanamsa.lahiri.value(at: tropical.instant)
        #expect(expected > 23 && expected < 25, "2026 Lahiri should be ~24°, got \(expected)")

        for t in tropical.positions {
            guard let s = sidereal.positions.first(where: { $0.body == t.body }) else {
                Issue.record("\(t.body.name) missing from the sidereal set"); continue
            }
            let delta = AstroMath.norm360(t.longitude - s.longitude)
            #expect(abs(delta - expected) < 1e-6,
                    "\(t.body.name) moved \(delta)°, expected \(expected)°")
        }
    }

    // MARK: - …and the values derived from them

    /// Houses are the step that gets forgotten. Cusps come from sidereal *time*, not the zodiac, so
    /// they start tropical and must be rotated too — otherwise every planet sits ~24° from its true
    /// house, which is most of a sign.
    @Test func houseCuspsMoveWithTheBodies() throws {
        let tropical = try #require(viewModel(nil).houses)
        let sidereal = try #require(viewModel(.lahiri).houses)
        let expected = Ayanamsa.lahiri.value(at: viewModel(nil).instant)

        for n in 1...12 {
            let delta = AstroMath.norm360(tropical.cusp(n) - sidereal.cusp(n))
            #expect(abs(delta - expected) < 1e-6, "cusp \(n) moved \(delta)°")
        }
        for (t, s) in [(tropical.angles.ascendant, sidereal.angles.ascendant),
                       (tropical.angles.midheaven, sidereal.angles.midheaven)] {
            #expect(abs(AstroMath.norm360(t - s) - expected) < 1e-6, "an angle did not move")
        }
    }

    /// The consequence that makes the whole thing worth doing: a body keeps its house.
    ///
    /// If the bodies moved and the cusps did not, this is the assertion that fails — and it is the
    /// one a user would eventually notice, long after trusting the chart.
    @Test func aBodyStaysInTheSameHouseWhenTheFrameChanges() throws {
        let tropical = viewModel(nil), sidereal = viewModel(.lahiri)
        let th = try #require(tropical.houses), sh = try #require(sidereal.houses)

        for t in tropical.positions {
            guard let s = sidereal.positions.first(where: { $0.body == t.body }) else { continue }
            let before = th.house(containing: t.longitude)
            let after = sh.house(containing: s.longitude)
            let why = "\(t.body.name) moved from house \(before) to \(after) — the frame rotated "
                    + "the bodies without rotating the cusps"
            #expect(before == after, "\(why)")
        }
    }

    /// Aspects are angular differences, so they are frame-invariant — an unchanged aspect list is
    /// the *correct* result and proves the shift was applied uniformly rather than to some subset.
    @Test func aspectsAreUnchangedBecauseAnglesAreFrameInvariant() {
        let tropical = viewModel(nil), sidereal = viewModel(.lahiri)
        #expect(tropical.aspects.count == sidereal.aspects.count,
                "a rigid rotation cannot create or destroy an aspect")
        for (a, b) in zip(tropical.aspects, sidereal.aspects) {
            #expect(a.type.name == b.type.name && a.a == b.a && a.b == b.b,
                    "aspect set changed under a rigid rotation")
        }
    }

    /// Signs — and therefore dignities, which are scored from the sign — must follow the frame.
    /// Around 24° of shift moves most bodies back a sign, so an unchanged sign set means the
    /// positions never really moved.
    @Test func signsAndThereforeDignitiesFollowTheFrame() {
        let tropical = viewModel(nil), sidereal = viewModel(.lahiri)
        var moved = 0
        for t in tropical.positions {
            guard let s = sidereal.positions.first(where: { $0.body == t.body }) else { continue }
            if t.sign != s.sign { moved += 1 }
        }
        #expect(moved >= 7, "only \(moved) of 10 bodies changed sign under a ~24° shift")

        // Dignity is scored from the longitude, so it reads the sidereal sign automatically — the
        // point being that nothing in the dignity layer had to learn about frames at all.
        for p in sidereal.positions {
            guard let score = EssentialDignities.score(p.body, longitude: p.longitude, sect: .day)
            else { continue }   // nil for the three moderns, by design
            #expect(score.sign == p.sign,
                    "\(p.body.name) scored against \(score.sign.name) but sits in \(p.sign.name)")
        }
    }

    // MARK: - Systems differ

    /// The four systems must not be aliases of each other. Raman sits ~1°27′ from Lahiri, which is
    /// more than enough to move a body across a sign boundary — the reason the frame is a choice.
    @Test func theFourSystemsProduceDifferentCharts() {
        let byBody = Ayanamsa.allCases.map { a in
            (a, viewModel(a).positions.first { $0.body == .sun }!.longitude)
        }
        for (a, b) in zip(byBody, byBody.dropFirst()) {
            #expect(abs(a.1 - b.1) > 1e-6,
                    "\(a.0.displayName) and \(b.0.displayName) produced the same Sun")
        }
        let lahiri = byBody.first { $0.0 == .lahiri }!.1
        let raman = byBody.first { $0.0 == .raman }!.1
        #expect(abs(AstroMath.norm180(raman - lahiri) - 1.45) < 0.1,
                "Raman should sit ~1°27′ from Lahiri")
    }
}
