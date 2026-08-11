import XCTest
import AltitudeKit
import DuctKit
import PipeKit
import PsychroKit
import UnitsKit
@testable import AirCore

/// # The altitude axis, at the view-model layer
///
/// The Kits are proven at three elevations in their own suites. What is proven here is that the
/// app *reaches* them with the site pressure — a tool that solved everything at sea level while
/// the chip said "5,280 ft" would pass every Kit test ever written.
final class AltitudeAxisTests: XCTestCase {

    private let seaLevel = Elevation.seaLevelPressure
    private let denver = Elevation.denver.barometricPressure
    private let mexicoCity = Elevation.mexicoCity.barometricPressure

    func testPsychrometricsChangesWithElevation() throws {
        let model = PsychrometricsModel()
        let states = try [seaLevel, denver, mexicoCity].map {
            try model.solved(pressure: $0).get()
        }
        // Humidity ratio at fixed dry bulb and RH rises with elevation, by a lot.
        XCTAssertGreaterThan(states[1].humidityRatio, states[0].humidityRatio * 1.20)
        XCTAssertGreaterThan(states[2].humidityRatio, states[1].humidityRatio)
        // Wet bulb falls.
        XCTAssertLessThan(states[1].wetBulb, states[0].wetBulb - 0.4)
        XCTAssertLessThan(states[2].wetBulb, states[1].wetBulb)
    }

    func testHeatLoadsChangeWithElevation() throws {
        let model = HeatModel()
        let sea = try model.solved(pressure: seaLevel).get()
        let high = try model.solved(pressure: mexicoCity).get()
        // Thinner air carries less heat at the same volume flow — 24 % less at Mexico City.
        XCTAssertLessThan(high.total, sea.total * 0.85)
        XCTAssertLessThan(high.massFlow, sea.massFlow)
    }

    func testDuctSizeChangesWithElevation() throws {
        let model = DuctModel()
        let sea = try model.solved(pressure: seaLevel, temperature: 20).get()
        let high = try model.solved(pressure: mexicoCity, temperature: 20).get()
        // Thinner air rubs less, so the same flow at the same friction fits a smaller duct.
        XCTAssertLessThan(high.diameter, sea.diameter)
        XCTAssertGreaterThan((sea.diameter - high.diameter) / sea.diameter, 0.02)
    }

    func testMixingChangesWithElevation() throws {
        let model = MixingModel()
        let sea = try model.solved(pressure: seaLevel).get()
        let high = try model.solved(pressure: mexicoCity).get()
        // The mixed dry bulb barely moves, but the moisture does — worth pinning both, because a
        // tool that quietly ignored pressure would also produce a stable dry bulb.
        XCTAssertEqual(sea.mixed.dryBulb, high.mixed.dryBulb, accuracy: 0.1)
        XCTAssertGreaterThan(high.mixed.humidityRatio, sea.mixed.humidityRatio * 1.2)
    }

    /// The fan tool takes two elevations of its own, and the density correction is the point of it.
    func testFanPressureAndPowerScaleWithDensityButFlowDoesNot() throws {
        let model = FanModel()
        let atSeaLevel = try model.solved().get()

        model.installedElevation = Elevation.denver.metres
        let atDenver = try model.solved().get()

        XCTAssertEqual(atSeaLevel.flow, atDenver.flow, accuracy: 1e-9,
                       "a fan is a constant-volume machine")
        XCTAssertLessThan(atDenver.pressure, atSeaLevel.pressure * 0.85)
        XCTAssertLessThan(atDenver.power, atSeaLevel.power * 0.85)
        XCTAssertEqual(atDenver.densityRatio, 0.823, accuracy: 0.005)
    }
}

/// # The known-pair axis
///
/// The scaffold this app grew from solved one pair. This walks the picker the way a user would.
final class KnownPairTests: XCTestCase {

    private let pressure = Elevation.seaLevelPressure

    func testEveryOfferedPairSolves() throws {
        let model = PsychrometricsModel()
        let truth = try model.solved(pressure: pressure).get()

        for first in PsychroInput.Kind.allCases {
            for second in PsychroInput.Kind.allCases {
                let candidate = PsychrometricsModel()
                guard !candidate.isUnavailable(first, opposite: second) else { continue }

                candidate.changeFirst(to: first, pressure: pressure)
                candidate.changeSecond(to: second, pressure: pressure)
                candidate.firstValue = first.value(of: truth)!
                candidate.secondValue = second.value(of: truth)!

                let solved = try candidate.solved(pressure: pressure).get()
                XCTAssertEqual(solved.dryBulb, truth.dryBulb, accuracy: 1e-3,
                               "\(first) + \(second) landed on the wrong dry bulb")
            }
        }
    }

    /// Pairs the solver refuses must be greyed out, not offered and then explained.
    func testUnavailablePairsAreExactlyTheOnesTheKitRefuses() {
        let model = PsychrometricsModel()
        XCTAssertTrue(model.isUnavailable(.dryBulb, opposite: .dryBulb))
        XCTAssertTrue(model.isUnavailable(.dewPoint, opposite: .humidityRatio))
        XCTAssertTrue(model.isUnavailable(.wetBulb, opposite: .enthalpy))
        XCTAssertTrue(model.isUnavailable(.enthalpy, opposite: .wetBulb))
        XCTAssertFalse(model.isUnavailable(.dryBulb, opposite: .relativeHumidity))
        XCTAssertFalse(model.isUnavailable(.wetBulb, opposite: .relativeHumidity))
    }

    /// Choosing a property that clashes with the other slot must move the *other* slot somewhere
    /// legal, not leave the screen in an error state the user did not ask for.
    func testPickingAClashingPropertyRepairsTheOtherSlot() {
        let model = PsychrometricsModel()
        model.firstKnown = .wetBulb
        model.secondKnown = .enthalpy          // degenerate; must be repaired
        XCTAssertFalse(model.isUnavailable(model.firstKnown, opposite: model.secondKnown),
                       "left in a state the solver refuses: "
                       + "\(model.firstKnown) + \(model.secondKnown)")

        model.firstKnown = .dewPoint
        model.secondKnown = .humidityRatio     // under-determined; must be repaired
        XCTAssertFalse(model.isUnavailable(model.firstKnown, opposite: model.secondKnown))
    }

    /// Changing which property a slot holds carries the current air across rather than jumping to
    /// an unrelated state.
    func testChangingAKnownCarriesTheStateAcross() throws {
        let model = PsychrometricsModel()
        let before = try model.solved(pressure: pressure).get()

        model.changeSecond(to: .wetBulb, pressure: pressure)
        let after = try model.solved(pressure: pressure).get()

        XCTAssertEqual(after.dryBulb, before.dryBulb, accuracy: 1e-6)
        XCTAssertEqual(after.humidityRatio, before.humidityRatio, accuracy: 1e-9)
    }

    /// Dragging the chart takes over both slots, because a pointer specifies dry bulb and moisture
    /// — anything else would leave the pickers fighting the point.
    func testDraggingTheChartTakesOverBothKnowns() {
        let model = PsychrometricsModel()
        model.firstKnown = .wetBulb
        model.secondKnown = .relativeHumidity
        model.setFromChart(dryBulb: 21, humidityRatio: 0.008)

        XCTAssertEqual(model.firstKnown, .dryBulb)
        XCTAssertEqual(model.secondKnown, .humidityRatio)
        XCTAssertEqual(model.firstValue, 21, accuracy: 1e-12)
        XCTAssertEqual(model.secondValue, 0.008, accuracy: 1e-12)
    }

    /// Invalid input must reach the screen as an error, not as a number.
    func testImpossibleInputProducesAnErrorNotAValue() {
        let model = PsychrometricsModel()
        model.firstKnown = .dryBulb
        model.firstValue = 20
        model.secondKnown = .wetBulb
        model.secondValue = 30                  // wet bulb above dry bulb: fog

        switch model.solved(pressure: pressure) {
        case .success(let state):
            XCTFail("expected a refusal, got \(state)")
        case .failure(let error):
            XCTAssertFalse(error.readableTitle.isEmpty)
            XCTAssertFalse(error.readableDetail.isEmpty)
        }
    }
}

/// # Persistence
///
/// The brief's requirement is blunt: state must survive backgrounding mid-calculation. That is a
/// test, not an intention.
final class PersistenceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        Persistence.defaults = UserDefaults(suiteName: "AirCoreTests")!
        Persistence.defaults.removePersistentDomain(forName: "AirCoreTests")
    }

    override func tearDown() {
        Persistence.defaults.removePersistentDomain(forName: "AirCoreTests")
        Persistence.defaults = .standard
        super.tearDown()
    }

    func testEveryToolSurvivesARelaunch() throws {
        let models = AppModels()
        models.psychrometrics.firstValue = 30.5
        models.psychrometrics.secondKnown = .wetBulb
        models.psychrometrics.secondValue = 21.25
        models.heat.volumeFlow = 1.234
        models.heat.solveFor = .flow
        models.mixing.outdoorFlow = 2.5
        models.duct.frictionRate = 1.5
        models.duct.roughness = .rough
        models.fan.newSpeed = 1750
        models.pipe.bore = 0.075
        models.pipe.method = .hazenWilliams
        models.saveAll()

        let restored = AppModels.loaded()
        XCTAssertEqual(restored.psychrometrics.firstValue, 30.5)
        XCTAssertEqual(restored.psychrometrics.secondKnown, .wetBulb)
        XCTAssertEqual(restored.psychrometrics.secondValue, 21.25)
        XCTAssertEqual(restored.heat.volumeFlow, 1.234)
        XCTAssertEqual(restored.heat.solveFor, .flow)
        XCTAssertEqual(restored.mixing.outdoorFlow, 2.5)
        XCTAssertEqual(restored.duct.frictionRate, 1.5)
        XCTAssertEqual(restored.duct.roughness, .rough)
        XCTAssertEqual(restored.fan.newSpeed, 1750)
        XCTAssertEqual(restored.pipe.bore, 0.075)
        XCTAssertEqual(restored.pipe.method, .hazenWilliams)
    }

    func testSettingsSurviveARelaunch() {
        let settings = AppSettings()
        settings.unitSystem = .si
        settings.elevationMetres = 1609.344
        settings.ductVelocityLimit = 7.5
        settings.waterIsHot = true
        settings.noteOpened(.duct)
        settings.noteOpened(.pipe)

        let restored = AppSettings.loaded()
        XCTAssertEqual(restored.unitSystem, .si)
        XCTAssertEqual(restored.elevationMetres, 1609.344, accuracy: 1e-9)
        XCTAssertEqual(restored.ductVelocityLimit, 7.5)
        XCTAssertTrue(restored.waterIsHot)
        XCTAssertEqual(restored.recentTools, [.pipe, .duct], "most recent first")
    }

    /// A model saved by an older build with a different shape must start fresh rather than take
    /// the app down.
    func testCorruptStateStartsFreshInsteadOfCrashing() {
        Persistence.defaults.set(Data("not json".utf8), forKey: "AirCore.tool.duct")
        let model = DuctModel.loaded()
        XCTAssertEqual(model.solveFor, .diameter, "expected the default model")
    }

    func testRecentToolsAreCappedAndDeduplicated() {
        let settings = AppSettings()
        for tool in Tool.allCases { settings.noteOpened(tool) }
        settings.noteOpened(.psychrometrics)

        XCTAssertEqual(settings.recentTools.count, 4)
        XCTAssertEqual(settings.recentTools.first, .psychrometrics)
        XCTAssertEqual(Set(settings.recentTools).count, settings.recentTools.count,
                       "no tool may appear twice")
    }
}

/// # Export
///
/// A CSV that loses its units, or breaks on a localised decimal comma, is not a record of anything.
final class ExportTests: XCTestCase {

    private let rows: [ResultGrid.Row] = [
        .init(title: "Wet bulb", value: 16.97, quantity: .temperature),
        .init(title: "Humidity ratio", value: 0.009277, quantity: .humidityRatio),
        .init(title: "Friction rate", value: 0.8164, quantity: .ductFrictionRate),
    ]

    func testTableCarriesValuesAndUnits() {
        let text = Export.table(rows, system: .ip)
        XCTAssertTrue(text.hasPrefix("Property\tValue\tUnit"))
        XCTAssertTrue(text.contains("°F"))
        XCTAssertTrue(text.contains("gr/lb"))
        XCTAssertTrue(text.contains("in wg/100 ft"))
        XCTAssertEqual(text.split(separator: "\n").count, rows.count + 1)
    }

    func testCSVCarriesProvenance() {
        let csv = Export.csv(rows, tool: .duct, system: .si, elevationMetres: 1609.344)
        XCTAssertTrue(csv.contains("# AirCore — Duct sizing"))
        XCTAssertTrue(csv.contains("# Units,SI"))
        XCTAssertTrue(csv.contains(Fmt.exportValueWithUnit(si: 1609.344, .elevation, .si)),
                      "the elevation the numbers belong to")
        XCTAssertTrue(csv.contains("Pa/m"))
    }

    /// A field with a comma in it has to be quoted or the file is not CSV.
    func testCSVQuotesFieldsContainingCommas() {
        let awkward: [ResultGrid.Row] = [.init(title: "Load, total", value: 12345,
                                               quantity: .heatLoad)]
        let csv = Export.csv(awkward, tool: .airsideHeat, system: .ip, elevationMetres: 0)
        XCTAssertTrue(csv.contains("\"Load, total\""))
    }

    /// Exported numbers must not carry a grouping separator: "1,609" in a CSV field is a field a
    /// spreadsheet will split, and this is the display path's one deliberate difference from the
    /// screen.
    func testExportedNumbersHaveNoGroupingSeparator() {
        let big: [ResultGrid.Row] = [.init(title: "Total", value: 3_516_852, quantity: .heatLoad)]
        let csv = Export.csv(big, tool: .airsideHeat, system: .si, elevationMetres: 0)
        XCTAssertEqual(Fmt.exportValue(si: 3_516_852, .heatLoad, .si), "3516852")
        XCTAssertTrue(csv.contains("3516852"), "got:\n\(csv)")
        // Deliberately not asserting what the *screen* form looks like: whether a locale groups,
        // and with which separator, is the locale's business. What matters is that the export
        // form is bare digits in every locale.
        XCTAssertTrue(Fmt.exportValue(si: 3_516_852, .heatLoad, .si)
                        .allSatisfy { $0.isNumber || $0 == "-" })
    }
}
