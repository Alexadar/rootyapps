import Testing
import Foundation
import GeometryKit
import ConcreteKit
import FramingKit
@testable import KerfCalc

/// The picker index → Kit input mappings in `ToolOptions.swift`.
///
/// These used to be `switch` statements inside SwiftUI `body`s, where nothing could reach them. The
/// failure they guard against is the quiet one: a wrong row hands an *otherwise correct* Kit the wrong
/// input, so every number renders, nothing crashes, and the answer is simply wrong. The state-space
/// rule applies — every position of every control, not just the default one.
@Suite struct ToolOptionsTests {

    // MARK: - Titles and mappings must be the same length

    /// A control with three titles and two mapped cases silently makes the third title an alias for the
    /// second. Assert the shapes agree, per picker.
    @Test func everyPickerMapsAsManyCasesAsItShowsTitles() {
        #expect(AreaShapeChoice.titles.count == 3)
        #expect(VolumeShapeChoice.titles.count == 2)
        #expect(ConcreteFormChoice.titles.count == 2)
        #expect(ConcreteBagChoice.titles.count == ConcreteBagChoice.yields.count)
        #expect(FootingKindChoice.titles.count == 3)
        #expect(StairCodeChoice.titles.count == 2)
        #expect(BarSizeChoice.titles.count == BarSize.allCases.count)
        #expect(AggregateMaterialChoice.titles.count == AggregateMaterial.allCases.count)
    }

    // MARK: - Area: every shape, and each distinct

    @Test func areaCoversEveryShape() {
        // 10 × 12: rectangle 120, triangle 60, circle πr² with r = 10.
        #expect(AreaShapeChoice.areaFt2(index: 0, a: 10, b: 12) == Area.rectangle(length: 10, width: 12))
        #expect(AreaShapeChoice.areaFt2(index: 1, a: 10, b: 12) == Area.triangle(base: 10, height: 12))
        #expect(AreaShapeChoice.areaFt2(index: 2, a: 10, b: 12) == Area.circle(radius: 10))

        // Each row must produce a DIFFERENT number, or a mis-wired row would be invisible.
        let all = (0...2).map { AreaShapeChoice.areaFt2(index: $0, a: 10, b: 12) }
        #expect(Set(all).count == 3, "two area shapes returned the same value: \(all)")
    }

    /// The circle ignores `b`; the other two must not.
    @Test func onlyTheCircleIgnoresTheSecondInput() {
        #expect(AreaShapeChoice.areaFt2(index: 2, a: 10, b: 12) == AreaShapeChoice.areaFt2(index: 2, a: 10, b: 99))
        #expect(AreaShapeChoice.areaFt2(index: 0, a: 10, b: 12) != AreaShapeChoice.areaFt2(index: 0, a: 10, b: 99))
        #expect(AreaShapeChoice.areaFt2(index: 1, a: 10, b: 12) != AreaShapeChoice.areaFt2(index: 1, a: 10, b: 99))
    }

    // MARK: - Volume: the cylinder's height comes from `c`, not `b`

    @Test func volumeCoversEveryShape() {
        #expect(VolumeShapeChoice.volumeFt3(index: 0, a: 10, b: 10, c: 8) == Volume.box(length: 10, width: 10, height: 8))
        #expect(VolumeShapeChoice.volumeFt3(index: 1, a: 10, b: 10, c: 8) == Volume.cylinder(diameter: 10, height: 8))
    }

    /// The trap: a cylinder has no "width", so `b` must not reach it. Reading height from `b` instead of
    /// `c` would still return a plausible cylinder volume.
    @Test func theCylinderIgnoresWidthAndUsesC() {
        #expect(VolumeShapeChoice.volumeFt3(index: 1, a: 10, b: 10, c: 8)
                == VolumeShapeChoice.volumeFt3(index: 1, a: 10, b: 99, c: 8))
        #expect(VolumeShapeChoice.volumeFt3(index: 1, a: 10, b: 10, c: 8)
                != VolumeShapeChoice.volumeFt3(index: 1, a: 10, b: 10, c: 9))
    }

    // MARK: - Concrete form and bag yield

    @Test func concreteFormCoversBothPours() {
        #expect(ConcreteFormChoice.cubicFeet(index: 0, lenFt: 10, widFt: 10, thickIn: 4, diaIn: 12, depthIn: 48)
                == Concrete.slabCubicFeet(lengthFt: 10, widthFt: 10, thicknessInches: 4))
        #expect(ConcreteFormChoice.cubicFeet(index: 1, lenFt: 10, widFt: 10, thickIn: 4, diaIn: 12, depthIn: 48)
                == Concrete.columnCubicFeet(diameterInches: 12, heightInches: 48))
    }

    /// The slab must ignore the column's inputs and vice versa — otherwise switching mode carries a
    /// stale dimension into the new formula.
    @Test func eachPourFormIgnoresTheOthersInputs() {
        #expect(ConcreteFormChoice.cubicFeet(index: 0, lenFt: 10, widFt: 10, thickIn: 4, diaIn: 12, depthIn: 48)
                == ConcreteFormChoice.cubicFeet(index: 0, lenFt: 10, widFt: 10, thickIn: 4, diaIn: 99, depthIn: 99))
        #expect(ConcreteFormChoice.cubicFeet(index: 1, lenFt: 10, widFt: 10, thickIn: 4, diaIn: 12, depthIn: 48)
                == ConcreteFormChoice.cubicFeet(index: 1, lenFt: 99, widFt: 99, thickIn: 99, diaIn: 12, depthIn: 48))
    }

    /// 80 / 60 / 40 lb bags yield 0.60 / 0.45 / 0.30 ft³. Descending, and distinct.
    @Test func bagYieldsDescendWithBagSize() {
        let ys = (0..<ConcreteBagChoice.titles.count).map { ConcreteBagChoice.yieldFt3(index: $0) }
        #expect(ys == [0.60, 0.45, 0.30])
        #expect(ys == ys.sorted(by: >), "a smaller bag must not yield more concrete")
    }

    // MARK: - Footing

    @Test func footingCoversEveryKind() {
        func cf(_ i: Int) -> Double {
            FootingKindChoice.cubicFeet(index: i, lenFt: 100, widIn: 16, depIn: 8,
                                        padL: 24, padW: 24, padD: 12,
                                        wallLen: 40, wallH: 4, wallT: 8)
        }
        #expect(cf(0) == Footing.continuousCubicFeet(lengthFt: 100, widthIn: 16, depthIn: 8))
        #expect(cf(1) == Footing.padCubicFeet(lengthIn: 24, widthIn: 24, depthIn: 12))
        #expect(cf(2) == Footing.wallCubicFeet(lengthFt: 40, heightFt: 4, thicknessIn: 8))
        #expect(Set([cf(0), cf(1), cf(2)]).count == 3, "two footing kinds returned the same volume")
    }

    /// A pad has no continuous run, so its rebar run is 0 — not the strip's length. Returning `lenFt`
    /// here would over-order rebar for every pad footing.
    @Test func onlyStripAndWallHaveARebarRun() {
        #expect(FootingKindChoice.runFeet(index: 0, lenFt: 100, wallLen: 40) == 100)
        #expect(FootingKindChoice.runFeet(index: 1, lenFt: 100, wallLen: 40) == 0)
        #expect(FootingKindChoice.runFeet(index: 2, lenFt: 100, wallLen: 40) == 40)
    }

    // MARK: - Enum-by-index accessors: order AND out-of-range safety

    /// `BarSize.allCases[1]` must be #4 — the default the Rebar and Footing screens open on. If the
    /// enum ever gains a case at the front, this catches it instead of the screen quietly showing #3.
    @Test func barSizeIndexOrderIsStable() {
        #expect(BarSizeChoice.size(index: 0) == BarSize.allCases[0])
        #expect(BarSizeChoice.size(index: 1).label == "#4", "the default rebar row is no longer #4")
        for (i, s) in BarSize.allCases.enumerated() { #expect(BarSizeChoice.size(index: i) == s) }
    }

    /// Out-of-range must clamp, not trap. `allCases[i]` used to be indexed directly with a picker index
    /// that `KERFCALC_SCREEN` can now seed from the environment.
    @Test func enumAccessorsClampInsteadOfCrashing() {
        #expect(BarSizeChoice.size(index: -1) == BarSize.allCases[0])
        #expect(BarSizeChoice.size(index: 999) == BarSize.allCases[0])
        #expect(AggregateMaterialChoice.material(index: -1) == AggregateMaterial.allCases[0])
        #expect(AggregateMaterialChoice.material(index: 999) == AggregateMaterial.allCases[0])
        #expect(ConcreteBagChoice.yieldFt3(index: -1) == 0.60)
        #expect(ConcreteBagChoice.yieldFt3(index: 999) == 0.60)
    }

    @Test func aggregateMaterialIndexOrderIsStable() {
        for (i, m) in AggregateMaterial.allCases.enumerated() {
            #expect(AggregateMaterialChoice.material(index: i) == m)
        }
    }

    // MARK: - Stair code

    /// Both rows, and they must differ — a picker that returns the same code either way is decorative.
    @Test func stairCodeCoversBothRows() {
        #expect(StairCodeChoice.code(index: 0) == StairCode.irc2021)
        #expect(StairCodeChoice.code(index: 1) == StairCode.ibc)
        #expect(StairCodeChoice.code(index: 0).maxRiser != StairCodeChoice.code(index: 1).maxRiser)
    }
}
