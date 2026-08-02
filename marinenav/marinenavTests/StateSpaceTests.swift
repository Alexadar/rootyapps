import XCTest
import TidesKit
@testable import Marine_Nav

/// §C.2 — the STATE SPACE, off the UI.
///
/// Combinatorial coverage through a real screen costs ~1.1 s per interaction, so it never gets
/// run. Against the view models it is microseconds. Exactly one UI assertion per control lives in
/// `CalculationChecks` to prove the binding is wired, because a model test cannot catch a view
/// bound to the wrong property.
///
/// These assert the app-layer state machine only. The arithmetic belongs to the Kits, which carry
/// 103 assertions against NOAA CO-OPS, Schureman SP-98, WMM2025, Vincenty/Karney and Bowditch.
@MainActor
final class StateSpaceTests: XCTestCase {

    // MARK: - The unit switch, every position and both directions
    //
    // This is the documented failure: a shipped watch app had a measurement-unit toggle that did
    // nothing — every number correct, every screen rendering, suite green — because the control
    // was only ever exercised in its default state.

    func testUnitSwitchConvertsAndReturns() {
        let m = TidesViewModel()
        XCTAssertEqual(m.unit, .feet, "feet is the shipped default")

        let feet = m.station.meanWaterLevel
        m.unit = .meters
        let metres = m.station.meanWaterLevel

        XCTAssertNotEqual(feet, metres, "flipping the unit must re-derive, not relabel")
        // NOAA 9414290: Z0 = 0.951 m = 3.12 ft. Exact international foot, 1 ft = 0.3048 m.
        XCTAssertEqual(metres, 0.951, accuracy: 0.002)
        XCTAssertEqual(feet, 3.12, accuracy: 0.01)
        XCTAssertEqual(feet * 0.3048, metres, accuracy: 0.01,
                       "the two unit sets must describe the same physical datum")

        m.unit = .feet
        XCTAssertEqual(m.station.meanWaterLevel, feet, accuracy: 1e-9,
                       "a one-way toggle is its own bug")
    }

    func testUnitSwitchChangesTheLabelAndThePrediction() {
        let m = TidesViewModel()
        let feetLabel = m.unitLabel
        let feetHeight = m.nowHeight
        m.unit = .meters
        XCTAssertNotEqual(m.unitLabel, feetLabel, "the label must follow the unit")
        XCTAssertEqual(m.unitLabel, "m")
        // Same instant, two unit systems: the metric height must be the foot height in metres.
        XCTAssertEqual(m.nowHeight, feetHeight * 0.3048, accuracy: 0.05,
                       "the predicted height must convert with the unit, not just the label")
    }

    // MARK: - StationDay: the bug that shipped
    //
    // `day` defaulted to the DEVICE's date, which `windowStart` then reinterpreted in the
    // STATION's zone. Whenever the two disagreed the screen opened on a window that did not
    // contain `now`: the curve, the extremes and the countdown described the following day while
    // the hero height stayed correct, and the now-line silently vanished.

    func testOpensOnTheStationsTodayNotTheDevices() {
        let m = TidesViewModel()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = m.record.timeZone
        let nowAtStation = cal.dateComponents([.year, .month, .day], from: Date())
        let opened = Calendar.current.dateComponents([.year, .month, .day], from: m.day)

        XCTAssertEqual(opened.year, nowAtStation.year)
        XCTAssertEqual(opened.month, nowAtStation.month)
        XCTAssertEqual(opened.day, nowAtStation.day,
                       "the window must open on the STATION's date, whatever this machine's is")
    }

    func testNowFallsInsideTheOpeningWindow() {
        for m in [TidesViewModel()] {
            let now = Date()
            XCTAssertTrue(now >= m.windowStart && now < m.windowEnd,
                          "`now` must lie in the opening window, or the now-line disappears")
            XCTAssertNotNil(m.nowFraction, "nowFraction nil means no now-line on the chart")
        }
    }

    func testCurrentsOpensOnTheStationsTodayToo() {
        let c = CurrentsViewModel()
        let now = Date()
        XCTAssertTrue(now >= c.windowStart && now < c.windowEnd)
        XCTAssertNotNil(c.nowFraction)
    }

    /// Changing station re-anchors the day only while the day was still the previous station's
    /// today — a deliberately chosen date must survive.
    func testStationChangeReanchorsOnlyAnUntouchedDay() throws {
        let m = TidesViewModel()
        guard StationCatalog.tideStations.count > 1 else {
            throw XCTSkip("needs two stations")
        }
        let other = StationCatalog.tideStations.first { $0.id != m.stationID }!

        // Untouched day: follows the new station.
        m.stationID = other.id
        XCTAssertEqual(m.day, StationDay.today(in: other.timeZone),
                       "an untouched day should follow the station")

        // Deliberately picked day: preserved.
        let picked = Calendar.current.date(byAdding: .day, value: -10, to: m.day)!
        m.day = picked
        let third = StationCatalog.tideStations.first { $0.id != other.id }!
        m.stationID = third.id
        XCTAssertEqual(m.day, picked, "a date the user picked must not be overwritten")
    }

    // MARK: - Day stepping, both directions

    func testDayStepsForwardAndBackInTheStationsZone() {
        let m = TidesViewModel()
        let start = m.windowStart
        m.day = Calendar.current.date(byAdding: .day, value: 1, to: m.day)!
        XCTAssertEqual(m.windowStart.timeIntervalSince(start), 86_400, accuracy: 3600,
                       "one day forward is one day, allowing for a DST boundary")
        m.day = Calendar.current.date(byAdding: .day, value: -1, to: m.day)!
        XCTAssertEqual(m.windowStart, start, "stepping back must return exactly")
    }

    func testWindowStartIsStationMidnightNotDeviceMidnight() {
        let m = TidesViewModel()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = m.record.timeZone
        let c = cal.dateComponents([.hour, .minute], from: m.windowStart)
        XCTAssertEqual(c.hour, 0, "windowStart must be midnight AT THE STATION")
        XCTAssertEqual(c.minute, 0)
    }

    func testExtremesAlternateAndLieInsideTheWindow() {
        let m = TidesViewModel()
        let e = m.extremes
        XCTAssertFalse(e.isEmpty, "a day at San Francisco has highs and lows")
        for event in e {
            XCTAssertTrue(event.date >= m.windowStart && event.date <= m.windowEnd,
                          "an extreme outside the plotted window would be drawn off-chart")
        }
        for (a, b) in zip(e, e.dropFirst()) {
            XCTAssertNotEqual(a.kind, b.kind, "highs and lows must alternate")
        }
    }

    // MARK: - Sight reduction: the index-error sign, both positions
    //
    // Off the arc ADDS, on the arc SUBTRACTS. A sign dropped here moves the line of position by
    // twice the index error, and the screen would still look perfectly plausible.

    func testIndexErrorSignBothWays() {
        let m = SightReductionViewModel()
        XCTAssertTrue(m.indexOffTheArc, "off the arc is the Bowditch example's state")

        let off = m.apparentAltitude
        XCTAssertTrue(m.indexCorrectionSigned.contains("+"), "off the arc must read as additive")

        m.indexOffTheArc = false
        let on = m.apparentAltitude
        XCTAssertTrue(m.indexCorrectionSigned.contains("−"), "on the arc must read as subtractive")

        XCTAssertGreaterThan(off, on, "off the arc must give the greater apparent altitude")
        // Flipping the side moves ha by twice the index error: 2 x 2.0' = 4.0' = 0.0667 deg.
        XCTAssertEqual(off - on, 2 * m.indexArcmin / 60, accuracy: 1e-9)

        m.indexOffTheArc = true
        XCTAssertEqual(m.apparentAltitude, off, accuracy: 1e-12, "and back again")
    }
}
