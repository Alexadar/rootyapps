import Testing
import Foundation
@testable import DimensionKit

// Oracle = dimensional analysis (exponent arithmetic on the length unit).  identity/invariant.
/// ORACLES:
///  • IDENTITY  — dimension algebra is exponent addition: linear x linear = square,
///    square x linear = cubic, cubic / square = linear, anything x scalar = anything.
///  • INVARIANT — results beyond cubic, or below scalar, are `nil` and NEVER clamped. `kerfcalc`'s
///    equivalent clamps with min(a+b,3)/max(a-b,0), which reports a fourth power as a volume.
///    A wrong answer presented as a right one is the failure this app exists to prevent.
@Suite("Dim — dimensional analysis")
struct DimTests {

    @Test("the trade cases that closed the incumbent's 12-year defect")
    func tradeCases() {
        #expect(Dim.linear * Dim.linear == .square,   "10' x 8' is an area")
        #expect(Dim.square * Dim.linear == .cubic,    "80 sq ft x 4\" is a volume")
        #expect(Dim.cubic / Dim.square == .linear,    "a volume over an area is a depth")
        #expect(Dim.linear / Dim.linear == .scalar,   "a ratio of lengths is a pure number")
        #expect(Dim.square / Dim.linear == .linear,   "an area over a length is a length")
    }

    @Test("a scalar multiplier preserves the dimension")
    func scalarPreserves() {
        for d in Dim.allCases {
            #expect(d * Dim.scalar == d, "\(d) x scalar must stay \(d)")
            #expect(d / Dim.scalar == d, "\(d) / scalar must stay \(d)")
        }
    }

    @Test("beyond cubic is nil, not clamped")
    func overflowIsNil() {
        #expect(Dim.cubic * Dim.linear == nil, "a fourth power is not a volume")
        #expect(Dim.square * Dim.square == nil, "area x area is not a volume")
        #expect(Dim.cubic * Dim.cubic == nil)
    }

    @Test("below scalar is nil, not clamped")
    func underflowIsNil() {
        #expect(Dim.scalar / Dim.linear == nil, "1 / length is not a pure number")
        #expect(Dim.linear / Dim.cubic == nil)
        #expect(Dim.square / Dim.cubic == nil)
    }

    @Test("multiplication is commutative and exponent arithmetic is consistent")
    func algebraIsConsistent() {
        for a in Dim.allCases {
            for b in Dim.allCases {
                #expect(a * b == b * a, "\(a) x \(b) must commute")
                if let p = a * b {
                    #expect(p.exponent == a.exponent + b.exponent)
                    #expect(p / b == a, "\(a) x \(b) / \(b) must return \(a)")
                } else {
                    #expect(a.exponent + b.exponent > Dim.cubic.exponent)
                }
            }
        }
    }

    @Test("display divisors convert inches^n to the unit shown")
    func displayDivisors() {
        #expect(Dim.linear.displayDivisor == 1)
        #expect(Dim.square.displayDivisor == 144,  "144 in² in a sq ft")
        #expect(Dim.cubic.displayDivisor == 1728,  "1728 in³ in a cu ft")
    }
}
