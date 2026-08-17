import Foundation

public enum Reachability {

    /// Can the frog get from `a` to `b`, at some (yaw, power) it can actually input?
    ///
    /// A single-pair convenience over the batch solver — one world, two slots. It is here for call
    /// sites that genuinely handle one jump (the aim preview, a repair probe) and for readability in
    /// tests. It is **not** a second implementation: the mathematics happens in `BatchSolver`, so a
    /// change there cannot leave this behind.
    public static func assess(from a: Rooftop, to b: Rooftop,
                              boosted: Bool = false,
                              in w: WorldConfig) -> JumpAssessment {
        let batch = BlockBatch(
            worlds: 1, slots: 2,
            centerX: Tensor(shape: [1, 2], data: [a.footprint.center.x, b.footprint.center.x]),
            centerZ: Tensor(shape: [1, 2], data: [a.footprint.center.z, b.footprint.center.z]),
            halfX: Tensor(shape: [1, 2], data: [a.footprint.halfX, b.footprint.halfX]),
            halfZ: Tensor(shape: [1, 2], data: [a.footprint.halfZ, b.footprint.halfZ]),
            height: Tensor(shape: [1, 2], data: [a.height, b.height]),
            alive: Tensor(shape: [1, 2], data: [1, 1]),
            spawn: [0], goal: [1]
        )
        let adj = BatchSolver.adjacency(batch, boosted: boosted, in: w)

        let p = 1                                  // pair (source 0, target 1)
        let reachable = adj.reachable[p] > 0.5
        let required = adj.requiredPower[p]
        let maxUsable = adj.maxUsablePower[p]

        return JumpAssessment(
            from: a.id, to: b.id,
            isReachable: reachable,
            requiredPower: reachable ? required : nil,
            maxUsablePower: reachable ? maxUsable : nil,
            powerWindow: reachable ? Swift.max(0, maxUsable - required) : 0,
            yaw: (b.footprint.center - a.footprint.center).heading,
            angularWidth: b.footprint.angularWidth(from: a.footprint.center),
            horizontalDistance: adj.horizontalDistance[p],
            rise: adj.rise[p]
        )
    }

    /// Minimum aim width any required jump may demand, radians (~4°).
    ///
    /// A jump can sit well inside the power envelope and still be unfair if the target subtends
    /// almost no angle from where you stand. Power and aim are separate failure modes, and the gate
    /// has to check both.
    public static let minimumAngularWidth: Double = 4 * .pi / 180

    /// Verify a district. This is the last thing that runs, on the final geometry, always.
    ///
    /// The fly is deliberately not consulted: the graph and grade here use the base envelope, so a
    /// district that is only crossable after eating a fly is rejected. The fly opens *optional*
    /// routes, and a guarantee that depends on a pickup is not a guarantee.
    public static func verify(_ block: CityBlock, in w: WorldConfig,
                              requiring band: DifficultyGrade.Band? = nil) -> Verdict {
        guard block.rooftops.count >= 2 else { return .degenerate("fewer than two rooftops") }
        guard block.spawn != block.goal else { return .degenerate("spawn is the goal") }

        let graph = ReachabilityGraph(block: block, config: w)
        guard let grade = DifficultyGrade.grade(block, in: w, using: graph) else {
            return .goalUnreachable
        }

        let traps = graph.trapRoofs
        guard traps.isEmpty else { return .trapRoofs(traps) }

        guard grade.meanBranchingFactor > 1.0 else { return .corridor(grade.meanBranchingFactor) }
        guard grade.tightestAngularWidth >= minimumAngularWidth else {
            return .aimTooTight(grade.tightestAngularWidth)
        }
        if let band, grade.band != band { return .cleared(grade) }
        return .cleared(grade)
    }
}

// MARK: - Line of flight
//
// Whether a tower stands in the way of a jump.
//
// This is deliberately NOT part of the reachability decision, and the reason is geometric rather
// than expedient. Rooftops sit on a lattice whose spacing is a large fraction of the frog's whole
// range, so a jump that passes *over* another rooftop is a jump of two lattice cells — and two
// cells is already beyond what full power reaches. Every jump the solver certifies is to an
// immediate neighbour, with nothing between the two roofs to hit.
//
// Folding a `[N, K, K, K]` obstacle test into the solver would multiply its cost by the slot count
// to rule out a case the geometry already rules out. So instead the assumption is stated here,
// checked by `LineOfFlightTests` against districts the generator actually produces, and will fail
// loudly if the lattice ever changes enough to make it false.
extension Reachability {

    /// Does the arc from `a` to `b` at the given power clear every other rooftop in the block?
    ///
    /// The trajectory is concave, so over the span where an obstacle's footprint crosses the aim
    /// ray, the arc's lowest point is at one end of that span — two evaluations decide it exactly,
    /// with no sampling.
    public static func clearsIntervening(from a: Rooftop, to b: Rooftop, power: Double,
                                         obstacles: [Rooftop], boosted: Bool = false,
                                         in w: WorldConfig) -> Bool {
        let origin = a.footprint.center
        let yaw = (b.footprint.center - origin).heading
        let v = Ballistics.speed(power: power, boosted: boosted, in: w)
        guard v > 0 else { return true }

        let landing = Ballistics.range(speed: v, rise: b.height - a.height, in: w) ?? .infinity

        for o in obstacles where o.id != a.id && o.id != b.id {
            guard o.height > a.height - w.frogHalfWidth else { continue }
            guard let span = o.footprint.rayEntryExit(from: origin, yaw: yaw) else { continue }
            guard span.upperBound > 0, span.lowerBound < landing else { continue }

            let riseToRoof = o.height - a.height
            for d in [Swift.max(span.lowerBound, 0), Swift.min(span.upperBound, landing)] {
                guard d > 0 else { continue }
                let t = d / (v * cos(w.launchElevation))
                let y = v * sin(w.launchElevation) * t - 0.5 * w.gravity * t * t
                if y < riseToRoof { return false }
            }
        }
        return true
    }
}
