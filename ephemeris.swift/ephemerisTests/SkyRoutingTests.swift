import Testing
import Foundation
import EphemerisKit
@testable import Ephemeris

/// The deep-link contract.
///
/// `EPHEMERIS_LENS` and `EPHEMERIS_TAB` are how every store screenshot and preview reel selects a
/// screen. `moon` and `hours` were lens values before they became pushed destinations, and they
/// must keep landing on the same content — a deep link that silently falls back to the default
/// produces a confidently captioned picture of the wrong screen, which has shipped here once.
@Suite("Sky routing")
struct SkyRoutingTests {

    // MARK: - Lenses still resolve as lenses

    @Test func theFourChartLensesResolveToLenses() {
        for lens in MomentLens.allCases {
            let r = SkyRouting.resolve(lens.rawValue)
            #expect(r.lens == lens, "\(lens.rawValue) should select a lens")
            #expect(r.destination == nil, "\(lens.rawValue) should not push a destination")
        }
    }

    /// The picker is back to four. Six segments do not fit an iPhone in sixteen languages, and this
    /// is the assertion that stops a fifth quietly reappearing.
    @Test func momentLensHasExactlyFourCases() {
        #expect(MomentLens.allCases.count == 4, "got \(MomentLens.allCases.map(\.rawValue))")
        #expect(MomentLens(rawValue: "moon") == nil, "moon must no longer be a lens")
        #expect(MomentLens(rawValue: "hours") == nil, "hours must no longer be a lens")
    }

    // MARK: - Destinations still resolve

    @Test func moonAndHoursResolveToDestinations() {
        for d in SkyDestination.allCases {
            let r = SkyRouting.resolve(d.rawValue)
            #expect(r.destination == d, "\(d.rawValue) should push its screen")
            #expect(r.lens == nil, "\(d.rawValue) should not also select a lens")
        }
    }

    /// Exactly one of the two is ever non-nil — otherwise a caller could both select a segment and
    /// push a screen from one value, and which one the user sees would depend on ordering.
    @Test func atMostOneOutcomeIsProducedForAnyInput() {
        let inputs = MomentLens.allCases.map(\.rawValue)
                   + SkyDestination.allCases.map(\.rawValue)
                   + ["", "nonsense", "MOON", "Wheel", "moon ", "0"]
        for raw in inputs {
            let r = SkyRouting.resolve(raw)
            #expect(!(r.lens != nil && r.destination != nil), "\(raw) produced both outcomes")
        }
    }

    // MARK: - Unknown input keeps the caller's default

    @Test func unrecognisedValuesResolveToNothing() {
        for raw in [nil, "", "nonsense", "MOON", "Hours", "wheel2"] as [String?] {
            let r = SkyRouting.resolve(raw)
            #expect(r.lens == nil && r.destination == nil,
                    "\(raw ?? "nil") should resolve to nothing, got \(r)")
        }
    }

    // MARK: - The legacy tab contract, unchanged

    /// `LegacyTab` must still map 0…5 exactly as it did. The capture pipeline sets these indices
    /// and three UI tests assert each reaches its own screen.
    @Test func legacyTabIndicesStillLandWhereTheyDid() {
        let expected: [(Int, ChartSection, MomentLens?, CyclesLens?)] = [
            (0, .sky,    .wheel,   nil),
            (1, .sky,    .table,   nil),
            (2, .sky,    .aspects, nil),
            (3, .cycles, nil,      .synodic),
            (4, .cycles, nil,      .timeline),
            (5, .charts, nil,      nil),
        ]
        for (index, section, moment, cycles) in expected {
            let d = LegacyTab.destination(for: index)
            #expect(d.section == section, "index \(index) → \(d.section), expected \(section)")
            #expect(d.moment == moment, "index \(index) moment lens changed")
            #expect(d.cycles == cycles, "index \(index) cycles lens changed")
        }
    }

    /// No fourth category. The links doc's rule is that anything not fitting Sky, Charts or Cycles
    /// is a different product — and a seat-filler would have to be invented to occupy it.
    @Test func thereAreStillExactlyThreeSections() {
        #expect(ChartSection.allCases.count == 3, "got \(ChartSection.allCases.map(\.rawValue))")
    }
}
