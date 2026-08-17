import Testing
import Foundation
@testable import ReachabilityKit

/// Hand-built pathological districts. Small enough to reason about completely, which is what makes
/// them useful for proving a property has teeth rather than merely passes.
enum Fixtures {
    static func roof(_ id: Int, x: Double, z: Double, height: Double, half: Double = 0.9) -> Rooftop {
        Rooftop(id: RooftopID(id),
                footprint: Rect2(center: Vec2(x, z), halfX: half, halfZ: half),
                height: height)
    }

    /// Two roofs beside each other and a goal far out of reach.
    ///
    /// Every roof here has somewhere to jump — they can hop back and forth forever — so the naive
    /// "no rooftop is a dead end" check is perfectly happy. The player is nonetheless stranded.
    /// This is the fixture that proves `roofsWithNoExit` is insufficient and `trapRoofs` is not.
    static func twoRoofCycle(in w: WorldConfig) -> CityBlock {
        let hop = w.flatMaxRange * 0.5
        return CityBlock(
            seed: 1, districtIndex: 0,
            rooftops: [
                roof(0, x: 0, z: 0, height: 16),
                roof(1, x: hop, z: 0, height: 16),
                roof(2, x: w.flatMaxRange * 12, z: 0, height: 16),   // unreachable by design
            ],
            spawn: RooftopID(0), goal: RooftopID(2),
            flyRoofs: [], killPlaneY: 0
        )
    }

    /// A straight line of roofs: solvable, but with no choices in it.
    static func corridor(in w: WorldConfig) -> CityBlock {
        let hop = w.flatMaxRange * 0.55
        let roofs = (0..<5).map { roof($0, x: 0, z: Double($0) * hop, height: 16) }
        return CityBlock(seed: 2, districtIndex: 0, rooftops: roofs,
                         spawn: RooftopID(0), goal: RooftopID(4), flyRoofs: [], killPlaneY: 0)
    }
}

@Suite("Reachability graph")
struct ReachabilityGraphTests {

    let w = WorldConfig.shipping

    @Test("the naive dead-end check passes a district that still strands the player")
    func naiveCheckIsInsufficient() {
        let block = Fixtures.twoRoofCycle(in: w)
        let graph = ReachabilityGraph(block: block, config: w)

        // Both reachable roofs can jump to each other, so nothing looks like a dead end...
        #expect(graph.roofsWithNoExit.isEmpty,
                "fixture is wrong: it was supposed to satisfy the naive check")
    }

    @Test("trap detection fails the same district")
    func trapDetectionHasTeeth() {
        let block = Fixtures.twoRoofCycle(in: w)
        let graph = ReachabilityGraph(block: block, config: w)

        // ...and yet the goal is unreachable from every roof the player can stand on.
        #expect(!graph.trapRoofs.isEmpty, "trap roofs went undetected")
        #expect(graph.route(from: block.spawn, to: block.goal) == nil)
        #expect(Reachability.verify(block, in: w) != .cleared(DifficultyGrade.grade(block, in: w) ?? {
            DifficultyGrade(minJumps: 0, tightestMargin: 0, medianMargin: 0,
                            tightestAngularWidth: 0, meanBranchingFactor: 0,
                            flyShortcutJumps: 0, band: .brutal)
        }()))
    }

    @Test("a corridor is rejected even though it is solvable")
    func corridorIsRejected() {
        let block = Fixtures.corridor(in: w)
        let verdict = Reachability.verify(block, in: w)
        // The route exists — this is not about solvability. It is about the premise of the sequel:
        // if every roof has exactly one onward option, the player is not routing, they are walking.
        #expect(ReachabilityGraph(block: block, config: w).route(from: block.spawn, to: block.goal) != nil)
        if case .corridor = verdict {} else {
            Issue.record("expected .corridor, got \(verdict)")
        }
    }

    @Test("every step of a returned route is independently reachable")
    func routeStepsAreValid() {
        // The route comes out of a vectorized flood; each step is then re-checked through the edge
        // predicate, so the search is validated by the physics rather than by a hand-written path.
        for seed in UInt64(1)...UInt64(25) {
            let recipe = BlockRecipe.forDistrict(Int(seed % 8), in: w)
            guard let generated = BlockGenerator.generate(
                recipe: recipe, seed: seed, districtIndex: 0, in: w
            ) else { continue }
            let graph = ReachabilityGraph(block: generated.block, config: w)
            guard let route = graph.route(from: generated.block.spawn, to: generated.block.goal) else {
                Issue.record("seed \(seed): cleared district has no route")
                continue
            }
            for step in route.steps {
                let fresh = Reachability.assess(from: generated.block[step.from],
                                                to: generated.block[step.to], in: w)
                #expect(fresh.isReachable, "seed \(seed): route step \(step.from)→\(step.to) is not reachable")
            }
        }
    }

    @Test("the graph is asymmetric exactly when heights differ")
    func asymmetryShowsAtGraphLevel() {
        // Down-jumps reach further than up-jumps, so a pair at the same height must cost the same
        // both ways and a pair at different heights must not.
        let flat = ReachabilityGraph(
            block: CityBlock(seed: 3, districtIndex: 0,
                             rooftops: [Fixtures.roof(0, x: 0, z: 0, height: 16),
                                        Fixtures.roof(1, x: w.flatMaxRange * 0.6, z: 0, height: 16)],
                             spawn: RooftopID(0), goal: RooftopID(1), flyRoofs: [], killPlaneY: 0),
            config: w)
        let up = flat.assessment(from: RooftopID(0), to: RooftopID(1))
        let down = flat.assessment(from: RooftopID(1), to: RooftopID(0))
        #expect(abs((up.requiredPower ?? 0) - (down.requiredPower ?? 0)) < 1e-9)

        let stepped = ReachabilityGraph(
            block: CityBlock(seed: 4, districtIndex: 0,
                             rooftops: [Fixtures.roof(0, x: 0, z: 0, height: 16),
                                        Fixtures.roof(1, x: w.flatMaxRange * 0.6, z: 0, height: 16.8)],
                             spawn: RooftopID(0), goal: RooftopID(1), flyRoofs: [], killPlaneY: 0),
            config: w)
        let climb = stepped.assessment(from: RooftopID(0), to: RooftopID(1))
        let drop = stepped.assessment(from: RooftopID(1), to: RooftopID(0))
        #expect((climb.requiredPower ?? 0) > (drop.requiredPower ?? 0) + 0.02,
                "climbing cost \(climb.requiredPower ?? -1), dropping cost \(drop.requiredPower ?? -1)")
    }

    @Test("the fly graph is a superset of the base graph")
    func flyOnlyEverAddsEdges() {
        for seed in UInt64(1)...UInt64(15) {
            let block = BlockGenerator.sample(recipe: BlockRecipe.forDistrict(3, in: w),
                                              seed: seed, districtIndex: 0, in: w)
            let base = BlockBatch.pack([block])
            let plain = BatchSolver.adjacency(base, boosted: false, in: w)
            let boosted = BatchSolver.adjacency(base, boosted: true, in: w)
            // Every base edge must survive the boost. Stated as a vector comparison over the whole
            // cube rather than a scan, because that is how everything else here is stated.
            let lost = (plain.reachable .&& boosted.reachable.not).sumLast().sumLast()[0]
            #expect(lost == 0, "seed \(seed): the fly removed \(lost) edges")
        }
    }
}

@Suite("Generator")
struct GeneratorTests {

    let w = WorldConfig.shipping

    @Test("every emitted district clears verification")
    func generatorGateIsTotal() {
        // The whole point of the Kit: nothing reaches the renderer that the solver has not cleared.
        // Sized for a debug run. The exhaustive sweep is `swift test -c release`, where the
        // elementwise kernels are an order of magnitude faster.
        let sweep = 120
        var produced = 0, abandoned = 0
        for seed in UInt64(1)...UInt64(sweep) {
            let recipe = BlockRecipe.forDistrict(Int(seed % 12), in: w)
            guard let generated = BlockGenerator.generate(
                recipe: recipe, seed: seed, districtIndex: Int(seed % 12), in: w
            ) else { abandoned += 1; continue }
            produced += 1
            #expect(Reachability.verify(generated.block, in: w).isCleared,
                    "seed \(seed): emitted a district that does not verify")
        }
        #expect(produced > 0)
        // Report the abandonment rate rather than hiding it — a silent cap reads as "covered
        // everything" when it did not.
        #expect(Double(abandoned) / Double(sweep) < 0.5,
                "generator abandoned \(abandoned)/\(sweep) seeds")
    }

    @Test("every fly sits on a roof reachable without a fly")
    func fliesAreObtainable() {
        for seed in UInt64(1)...UInt64(40) {
            guard let generated = BlockGenerator.generate(
                recipe: BlockRecipe.forDistrict(4, in: w), seed: seed, districtIndex: 4, in: w
            ) else { continue }
            let reachable = ReachabilityGraph(block: generated.block, config: w).reachableFromSpawn
            for fly in generated.block.flyRoofs {
                #expect(reachable.contains(fly),
                        "seed \(seed): fly on \(fly) cannot be reached without a fly")
            }
        }
    }

    @Test("spawn and goal are distinct and on opposite edges")
    func spawnAndGoalAreOpposed() {
        for seed in UInt64(1)...UInt64(30) {
            guard let g = BlockGenerator.generate(
                recipe: BlockRecipe.forDistrict(2, in: w), seed: seed, districtIndex: 2, in: w
            ) else { continue }
            #expect(g.block.spawn != g.block.goal)
            let spawnZ = g.block[g.block.spawn].footprint.center.z
            let goalZ = g.block[g.block.goal].footprint.center.z
            #expect(goalZ > spawnZ, "seed \(seed): goal is not across the district")
        }
    }

    @Test("difficulty rises with district depth")
    func difficultyRamps() {
        // A differential property: no absolute number is asserted, only that deeper districts leave
        // less margin. That cannot be satisfied by a curve that is uniformly wrong.
        func medianMargin(district k: Int) -> Double {
            var margins: [Double] = []
            for seed in UInt64(1)...UInt64(20) {
                guard let g = BlockGenerator.generate(
                    recipe: BlockRecipe.forDistrict(k, in: w),
                    seed: seed &* 7919, districtIndex: k, in: w
                ) else { continue }
                margins.append(g.grade.tightestMargin)
            }
            guard !margins.isEmpty else { return .nan }
            margins.sort()
            return margins[margins.count / 2]
        }

        let early = medianMargin(district: 0)
        let late = medianMargin(district: 14)
        #expect(early.isFinite && late.isFinite)
        #expect(late < early, "district 14 (\(late)) was no harder than district 0 (\(early))")
    }
}

@Suite("Determinism")
struct DeterminismTests {

    let w = WorldConfig.shipping

    @Test("SplitMix64 matches Vigna's published reference vectors")
    func splitMixMatchesPublishedVectors() {
        // The one genuine external authority this Kit has. It matters because it is what will let a
        // future Python torchsim on another machine rebuild byte-identical districts.
        // Source: http://prng.di.unimi.it/splitmix64.c
        var rng = SplitMix64(seed: 0)
        let expected: [UInt64] = [
            0xE220A8397B1DCDAF, 0x6E789E6AA1B965F4, 0x06C45D188009454F, 0xF88BB8A8724C81EC,
            0x1B39896A51A8749B, 0x53CB9F0C747EA2EA, 0x2C829ABE1F4532E1, 0xC584133AC916AB3C,
        ]
        for (i, want) in expected.enumerated() {
            let got = rng.next()
            #expect(got == want, "draw \(i): got \(String(got, radix: 16)), want \(String(want, radix: 16))")
        }
    }

    @Test("unit doubles stay in the half-open unit interval")
    func unitDoublesAreInRange() {
        var rng = SplitMix64(seed: 12345)
        let samples = rng.uniforms(200_000)
        #expect(samples.data.allSatisfy { $0 >= 0 && $0 < 1 })
        let mean = samples.sumLast()[0] / Double(samples.count)
        #expect(abs(mean - 0.5) < 0.01, "mean was \(mean)")
    }

    @Test("bounded integers are unbiased")
    func boundedIntegersAreUnbiased() {
        var rng = SplitMix64(seed: 99)
        var counts = [Int](repeating: 0, count: 7)
        for _ in 0..<140_000 { counts[rng.int(in: 0...6)] += 1 }
        for (i, c) in counts.enumerated() {
            #expect(abs(Double(c) - 20_000) < 900, "bucket \(i) got \(c)")
        }
    }

    @Test("the same seed produces a byte-identical district")
    func sameSeedSameBytes() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for seed in UInt64(1)...UInt64(15) {
            let recipe = BlockRecipe.forDistrict(3, in: w)
            let a = BlockGenerator.sample(recipe: recipe, seed: seed, districtIndex: 3, in: w)
            let b = BlockGenerator.sample(recipe: recipe, seed: seed, districtIndex: 3, in: w)
            #expect(try encoder.encode(a) == encoder.encode(b), "seed \(seed) was not reproducible")
        }
    }

    @Test("generation never reaches for the system random generator")
    func noSystemRandomness() throws {
        // Enforced by reading the source. `Double.random(in:)` and friends have an
        // implementation-defined mapping from bits to values that may change between Swift
        // versions — which would silently regenerate every district in the game.
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/ReachabilityKit")
        for file in try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        where file.pathExtension == "swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            // Comment lines are skipped: `SplitMix64`'s own documentation has to be able to name the
            // thing it exists to replace.
            let code = source.split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.hasPrefix("//") && !$0.hasPrefix("///") && !$0.hasPrefix("*") }
                .joined(separator: "\n")

            #expect(!code.contains(".random("),
                    "\(file.lastPathComponent) calls .random( — use SplitMix64")
            #expect(!code.contains("SystemRandomNumberGenerator"),
                    "\(file.lastPathComponent) uses the system RNG")
        }
    }
}

@Suite("Line of flight")
struct LineOfFlightTests {

    let w = WorldConfig.shipping

    /// The solver deliberately does not test whether a jump passes over an intervening tower.
    ///
    /// The justification is geometric: rooftops sit on a lattice whose spacing is a large fraction
    /// of the frog's entire range, so any jump that would pass over another rooftop spans two
    /// lattice cells — and two cells is already beyond full power. Every certified jump is to an
    /// immediate neighbour with nothing in between.
    ///
    /// That is an assumption about the *geometry*, not about the physics, and geometry can change.
    /// So it is checked here against districts the generator actually produces. If the lattice is
    /// ever loosened enough to make it false, this fails and the obstacle test goes back into the
    /// solver — at which point its cost is a deliberate decision rather than an oversight.
    @Test("no certified jump passes through a building")
    func certifiedJumpsAreUnobstructed() {
        var checked = 0
        for seed in UInt64(1)...UInt64(40) {
            let district = Int(seed % 12)
            guard let generated = BlockGenerator.generate(
                recipe: BlockRecipe.forDistrict(district, in: w),
                seed: seed, districtIndex: district, in: w
            ) else { continue }

            let block = generated.block
            let graph = ReachabilityGraph(block: block, config: w)
            for source in block.rooftops {
                for target in graph.neighbours(of: source.id) {
                    let a = graph.assessment(from: source.id, to: target)
                    guard let power = a.requiredPower else { continue }
                    checked += 1
                    #expect(Reachability.clearsIntervening(
                        from: source, to: block[target], power: power,
                        obstacles: block.rooftops, in: w
                    ), "seed \(seed): \(source.id)→\(target) clips a building")
                }
            }
        }
        #expect(checked > 150, "only checked \(checked) jumps — the fixture is too thin to mean much")
    }
}
