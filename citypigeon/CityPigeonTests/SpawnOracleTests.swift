import XCTest
import MLX
@testable import CityPigeon

/// The spawner promises every target is hittable. This suite is what makes that a claim rather than
/// a hope, and it checks the promise with mathematics the spawner does not use.
final class SpawnOracleTests: XCTestCase {

    let w = WorldConfig.shipping
    var kinds: [(String, TargetProfile)] { [("car", w.car), ("pedestrian", w.pedestrian)] }

    /// The band must exist for every kind, or the tuning is broken.
    func testTheAdmissibleBandExistsAndIsInsideTheAuthoredEnvelope() {
        for (name, p) in kinds {
            guard let band = Spawn.admissibleSpeeds(p, in: w) else {
                return XCTFail("\(name): no target speed produces a fair window")
            }
            print("\(name): admissible speeds \(fmt(band.lowerBound))…\(fmt(band.upperBound)) m/s "
                  + "(authored \(fmt(p.speedRange.lowerBound))…\(fmt(p.speedRange.upperBound)))")
            XCTAssertGreaterThanOrEqual(band.lowerBound, p.speedRange.lowerBound - 1e-9)
            XCTAssertLessThanOrEqual(band.upperBound, p.speedRange.upperBound + 1e-9)
            XCTAssertGreaterThan(band.upperBound - band.lowerBound, 1.0,
                                 "\(name): the band is so narrow that all traffic moves at one speed")
        }
    }

    /// **Every speed the spawner can draw must verify as fair.** Since the band is closed form, a
    /// failure here means the algebra is wrong, not that a sample was unlucky.
    func testEverySampleableSpeedProducesAFairWindow() {
        for (name, p) in kinds {
            guard let band = Spawn.admissibleSpeeds(p, in: w) else { return XCTFail("\(name): no band") }
            for i in 0...400 {
                let vt = band.lowerBound + (band.upperBound - band.lowerBound) * Double(i) / 400
                guard let gap = Spawn.spawnGap(targetSpeed: vt, p, in: w) else {
                    return XCTFail("\(name): no on-screen spawn gap exists at v_t = \(vt)")
                }
                switch Spawn.verify(targetSpeed: vt, gap: gap, p, in: w) {
                case .fair: continue
                case let other: XCTFail("\(name) at v_t = \(fmt(vt)): \(other)")
                }
            }
        }
    }

    /// **The `Δv` vs `lead_max` bug dies here.**
    ///
    /// Placing an oncoming target at the pigeon's own maximum lead rather than at `Δv·T_max + r`
    /// puts it inside its window at the instant it appears. Assert the spawner's gap is strictly
    /// larger for every oncoming target, and that the naive gap really would fail.
    func testOncomingTargetsSpawnBeyondThePigeonsOwnLead() {
        let p = w.car
        let pigeonLead = w.cruiseSpeed * Spawn.maxFlightTime(p, in: w)
        var checkedOncoming = 0

        guard let band = Spawn.admissibleSpeeds(p, in: w) else { return XCTFail("no band") }
        for i in 0...200 {
            let vt = band.lowerBound + (band.upperBound - band.lowerBound) * Double(i) / 200
            guard let gap = Spawn.spawnGap(targetSpeed: vt, p, in: w) else { continue }
            guard vt < 0 else { continue }                       // oncoming only

            XCTAssertGreaterThan(gap, pigeonLead,
                                 "an oncoming target at v_t=\(fmt(vt)) spawns at \(fmt(gap)) m, "
                                 + "inside the pigeon's own \(fmt(pigeonLead)) m lead")
            // And the naive placement really is broken, so the test is not decorative.
            if case .fair = Spawn.verify(targetSpeed: vt, gap: pigeonLead, p, in: w) {
                XCTFail("the naive lead_max gap was accepted at v_t=\(fmt(vt)) — this test proves "
                        + "nothing if the wrong answer also passes")
            }
            checkedOncoming += 1
        }
        print("SPAWN oncoming: \(checkedOncoming) speeds all spawn beyond lead_max = \(fmt(pigeonLead)) m")
        XCTAssertGreaterThan(checkedOncoming, 20)
    }

    /// Independent confirmation: simulate the encounter frame by frame and ask `Interception`
    /// directly. Nothing from `Spawn` decides where the window is.
    func testTheWindowIsWhereAFrameSweepSaysItIs() {
        let p = w.car
        guard let band = Spawn.admissibleSpeeds(p, in: w) else { return XCTFail("no band") }

        for vt in [band.lowerBound, (band.lowerBound + band.upperBound) / 2, band.upperBound] {
            guard let gap = Spawn.spawnGap(targetSpeed: vt, p, in: w),
                  case let .fair(win) = Spawn.verify(targetSpeed: vt, gap: gap, p, in: w)
            else { return XCTFail("no fair window at v_t = \(vt)") }

            // Walk the encounter at the simulation rate and count the frames where a charge exists.
            var solvableFrames = 0
            let steps = Int(12.0 / w.dt)
            for i in 0..<steps {
                let t = Double(i) * w.dt
                let currentGap = gap - (w.cruiseSpeed - vt) * t
                if currentGap < -20 { break }
                let win = Interception.window(
                    pigeonX: MLXArray(Float(0)), pigeonY: MLXArray(Float(w.cruiseAltitude)),
                    forwardSpeed: MLXArray(Float(w.cruiseSpeed)), climb: MLXArray(Float(0)),
                    targetX: MLXArray(Float(currentGap)), targetSpeed: MLXArray(Float(vt)),
                    targetTopY: MLXArray(Float(p.topY)), radius: MLXArray(Float(w.hitRadius(p))), in: w)
                if win.valid.item(Bool.self) { solvableFrames += 1 }
            }

            let measured = Double(solvableFrames) * w.dt
            print("SPAWN v_t=\(fmt(vt)): predicted \(fmt(win.duration)) s, frame sweep \(fmt(measured)) s")
            XCTAssertGreaterThan(measured, w.minFairWindow,
                                 "the measured window is shorter than the fairness floor")
            // Within a couple of frames. The prediction uses the worst-case charge span over the
            // guarantee box while the sweep flies the nominal state, so the sweep should be at
            // least as generous.
            XCTAssertGreaterThanOrEqual(measured, win.duration - 4 * w.dt,
                                        "the closed-form window over-promises against a real sweep")
        }
    }

    /// A window that never closes is farmable.
    func testEveryWindowCloses() {
        for (name, p) in kinds {
            guard let band = Spawn.admissibleSpeeds(p, in: w) else { return XCTFail("\(name)") }
            for vt in [band.lowerBound, band.upperBound] {
                guard let gap = Spawn.spawnGap(targetSpeed: vt, p, in: w),
                      case let .fair(win) = Spawn.verify(targetSpeed: vt, gap: gap, p, in: w)
                else { return XCTFail("\(name) at \(vt)") }
                XCTAssertTrue(win.duration.isFinite && win.duration < 30,
                              "\(name): a \(win.duration) s window is effectively unbounded")
            }
        }
    }

    /// A target that is not being caught up with is refused rather than given a window.
    func testATargetOutrunningThePigeonIsRefused() {
        for (_, p) in kinds {
            XCTAssertEqual(Spawn.verify(targetSpeed: w.cruiseSpeed + 3, gap: 30, p, in: w),
                           .neverCloses)
            XCTAssertNil(Spawn.spawnGap(targetSpeed: w.cruiseSpeed, p, in: w))
        }
    }

    // MARK: - Determinism

    /// Same seed and frame ⇒ identical draws, regardless of what else has been drawn.
    func testSamplingIsStatelessAndReproducible() {
        let a = Spawn.sampleSpeeds(shape: [4, 6], w.car, in: w, seed: 42, frame: 1000)
        _ = Spawn.sampleSpeeds(shape: [4, 6], w.car, in: w, seed: 42, frame: 1001)   // interleave
        let b = Spawn.sampleSpeeds(shape: [4, 6], w.car, in: w, seed: 42, frame: 1000)
        XCTAssertEqual(a.asArray(Float.self), b.asArray(Float.self),
                       "the same (seed, frame) gave different draws — there is hidden state")
    }

    func testDifferentSeedsAndFramesDiverge() {
        let base = Spawn.sampleSpeeds(shape: [64], w.car, in: w, seed: 1, frame: 10).asArray(Float.self)
        let otherSeed = Spawn.sampleSpeeds(shape: [64], w.car, in: w, seed: 2, frame: 10).asArray(Float.self)
        let otherFrame = Spawn.sampleSpeeds(shape: [64], w.car, in: w, seed: 1, frame: 11).asArray(Float.self)
        XCTAssertNotEqual(base, otherSeed)
        XCTAssertNotEqual(base, otherFrame)
    }

    /// Every draw lands inside the band. If this ever fails, targets exist that the guarantee does
    /// not cover — the exact failure the closed-form band is meant to make impossible.
    func testEveryDrawLandsInsideTheAdmissibleBand() {
        for (name, p) in kinds {
            guard let band = Spawn.admissibleSpeeds(p, in: w) else { return XCTFail("\(name)") }
            for frame in 0..<200 {
                let s = Spawn.sampleSpeeds(shape: [32], p, in: w, seed: 7, frame: frame)
                for v in s.asArray(Float.self) {
                    XCTAssertTrue(Double(v) >= band.lowerBound - 1e-4
                                  && Double(v) <= band.upperBound + 1e-4,
                                  "\(name): drew \(v) outside \(band)")
                }
            }
        }
    }

    /// Vigna's published SplitMix64 reference vectors — the only genuinely third-party oracle here.
    /// Every other number in this engine was chosen by someone on this project.
    func testSplitMix64MatchesThePublishedReferenceVectors() {
        // Successive outputs for the seed stream starting at 0, per Vigna's reference implementation.
        let expected: [UInt64] = [
            0xE220A8397B1DCDAF, 0x6E789E6AA1B965F4, 0x06C45D188009454F,
            0xF88BB8A8724C81EC, 0x1B39896A51A8749B,
        ]
        var state: UInt64 = 0
        for (i, want) in expected.enumerated() {
            state = state &+ 0x9E37_79B9_7F4A_7C15
            let got = Rng.splitMix64(state &- 0x9E37_79B9_7F4A_7C15)
            XCTAssertEqual(got, want, "SplitMix64 output \(i) does not match the published vector")
        }
    }

    private func fmt(_ d: Double) -> String { String(format: "%.2f", d) }
}
