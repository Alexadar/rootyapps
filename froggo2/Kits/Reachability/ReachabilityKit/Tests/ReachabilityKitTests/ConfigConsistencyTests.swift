import Testing
import Foundation
@testable import ReachabilityKit

/// Does the tuning actually hang together?
///
/// These are the arithmetic checks I first did in my head and got wrong: the initial draft shipped
/// rooftops that were **wider than the maximum jump**, which makes every district unsolvable by
/// construction. Nothing in the ballistics was incorrect — the constants simply did not fit each
/// other. A solver that is provably right about an impossible world is still a game nobody can play.
///
/// So the relationships between constants are asserted, not assumed, and they are asserted against
/// geometry the generator actually produces rather than against my estimate of it.
@Suite("World configuration is self-consistent")
struct ConfigConsistencyTests {

    let w = WorldConfig.shipping

    @Test("a rooftop is smaller than the frog's reach")
    func roofsFitInsideTheEnvelope() {
        let widestRoof = w.roofHalfExtentRange.upperBound * 2
        #expect(widestRoof < w.flatMaxRange,
                "roofs are \(widestRoof) m across but the frog only jumps \(w.flatMaxRange) m")
    }

    @Test("the landing inset never consumes a rooftop")
    func insetLeavesUsableRoof() {
        // Impact at full power is the hardest arrival the game can produce, so it is the inset that
        // matters. If it exceeded the smallest roof's half-extent, that roof could never be landed
        // on at all and the generator would be sampling unusable geometry.
        guard let impact = Ballistics.impactSpeed(speed: w.maxLaunchSpeed, rise: 0, in: w) else {
            Issue.record("no impact at full power")
            return
        }
        let inset = Ballistics.landingInset(impact: impact, in: w)
        let smallestHalf = w.roofHalfExtentRange.lowerBound
        #expect(inset < smallestHalf,
                "inset \(inset) m leaves nothing of a \(smallestHalf) m half-roof")
    }

    @Test("the tightest lattice cannot make rooftops overlap")
    func roofsNeverOverlapAtTightestSpacing() {
        let recipe = BlockRecipe.forDistrict(0, in: w)
        let closestCentres = recipe.cellSize * (1 - 2 * recipe.jitter)
        let widest = w.roofHalfExtentRange.upperBound * 2
        #expect(closestCentres > widest,
                "closest centres \(closestCentres) m vs two half-roofs \(widest) m")
    }

    @Test("the widest jump the generator can ask for is inside the envelope")
    func hardestGeneratedJumpFits() {
        // Deepest district = tightest spacing. Two neighbours can jitter apart at the same time,
        // so the worst centre-to-centre span is the cell size stretched by twice the jitter.
        let recipe = BlockRecipe.forDistrict(20, in: w)
        let worstCentres = recipe.cellSize * (1 + 2 * recipe.jitter)
        // The frog does not need to reach the far roof's centre — only far enough onto it to settle.
        let mustReach = worstCentres - w.roofHalfExtentRange.upperBound
            + Ballistics.landingInset(
                impact: Ballistics.impactSpeed(speed: w.maxLaunchSpeed, rise: 0, in: w)!, in: w
            )
        let available = w.flatMaxRange * w.powerCeiling
        #expect(mustReach < available,
                "hardest jump needs \(mustReach) m of \(available) m available")
    }

    @Test("an uphill neighbour is always still climbable at the tightest spacing")
    func heightFieldStaysClimbable() {
        // The binding constraint is not the bare apex. Climbing costs range: a jump that gains `h`
        // over distance `d` needs `v² = g·d²/(d − h)` at 45°, so the steeper the climb the less
        // distance is left for it. The real question is therefore "at the spacing of the deepest
        // district, how much rise can the frog still afford?" — and the height field has to stay
        // under *that*, not under the apex.
        let deepest = BlockRecipe.forDistrict(20, in: w)
        let d = deepest.cellSize * (1 + deepest.jitter)          // a stretched neighbour hop
        let vCeiling = w.maxLaunchSpeed * w.powerCeiling

        // Largest rise still solvable at that distance.
        var affordableRise = 0.0
        for candidate in stride(from: 0.0, through: w.maxRise, by: 0.005) {
            guard let v = Ballistics.requiredSpeed(range: d, rise: candidate, in: w),
                  v <= vCeiling else { break }
            affordableRise = candidate
        }
        #expect(affordableRise > 0.2, "no meaningful climb is affordable at \(d) m spacing")

        // Now measure what the generator actually produces between adjacent roofs.
        var worst = 0.0
        for seed in UInt64(1)...UInt64(150) {
            let recipe = BlockRecipe.forDistrict(Int(seed % 12), in: w)
            let block = BlockGenerator.sample(recipe: recipe, seed: seed, districtIndex: 0, in: w)
            for a in block.rooftops {
                for b in block.rooftops where b.id != a.id {
                    let centres = a.footprint.center.distance(to: b.footprint.center)
                    guard centres < recipe.cellSize * 1.5 else { continue }   // neighbours only
                    worst = max(worst, abs(b.height - a.height))
                }
            }
        }
        #expect(worst < affordableRise,
                "neighbours differ by up to \(worst) m, but only \(affordableRise) m is climbable")
    }

    @Test("the derived quantities are the ones froggo 1's feel is expressed in")
    func derivedQuantitiesAreSane() {
        // Not exact ports — froggo 1's jumpForce lived in an unstated unit — but the shape of the
        // arc is the feel, and these are the numbers that shape it. Recorded so that a change to
        // the scale shows up here as a deliberate edit rather than as silent drift.
        #expect(w.flatApex == w.maxRise)
        #expect(abs(w.flatApex - w.flatMaxRange / 4) < 1e-9)   // the 45° identity
        #expect(w.flatHangTime > 1.0 && w.flatHangTime < 1.6,
                "hang time \(w.flatHangTime)s is outside the floaty-but-not-slow band")
        #expect(w.boosted.flatMaxRange / w.flatMaxRange > 2.2)  // the fly opens routes, not inches
    }
}
