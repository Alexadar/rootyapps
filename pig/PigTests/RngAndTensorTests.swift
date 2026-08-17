import XCTest
@testable import Pig

/// The vector layer and the random source — the two files every other test stands on.
final class RngAndTensorTests: XCTestCase {

    // MARK: - Rng

    /// **The only genuinely third-party oracle in this engine.**
    ///
    /// Every other constant here was chosen by someone on this project; SplitMix64 has published
    /// reference vectors, so this test compares against a number nobody involved invented. Vectors
    /// from Vigna's reference implementation, seeded 0, first four outputs.
    func testSplitMix64MatchesThePublishedReferenceVectors() {
        let expected: [UInt64] = [0xE220A8397B1DCDAF, 0x6E789E6AA1B965F4,
                                  0x06C45D188009454F, 0xF88BB8A8724C81EC]
        // `Rng.splitMix64` takes the counter and adds the golden ratio itself, so the reference
        // generator's n-th output — which mixes `seed + n·golden` — is this function applied to
        // `(n − 1)·golden`, starting from a seed of zero.
        for (i, want) in expected.enumerated() {
            XCTAssertEqual(Rng.splitMix64(UInt64(i) &* 0x9E37_79B9_7F4A_7C15), want,
                           "SplitMix64 output \(i) does not match the reference vector")
        }
    }

    func testUniformsAreInRangeAndFillTheInterval() {
        let u = Rng.uniform([4096], seed: 7, frame: 3, stream: .dropAngle)
        XCTAssertEqual(u.count, 4096)
        for x in u.data {
            XCTAssertGreaterThanOrEqual(x, 0)
            XCTAssertLessThan(x, 1)
        }
        let mean = u.data.reduce(0, +) / Double(u.count)
        XCTAssertEqual(mean, 0.5, accuracy: 0.02, "the draw is biased")

        // Ten buckets, none empty and none dominant — a cheap uniformity check that would catch a
        // hash collapsing onto a lattice.
        var buckets = [Int](repeating: 0, count: 10)
        for x in u.data { buckets[min(9, Int(x * 10))] += 1 }
        for (i, n) in buckets.enumerated() {
            XCTAssertGreaterThan(n, 250, "bucket \(i) is nearly empty")
            XCTAssertLessThan(n, 650, "bucket \(i) is over-full")
        }
    }

    /// Streams must be independent, or adding one roll to the step would silently change every value
    /// drawn after it and quietly alter the game.
    func testStreamsAndFramesAreIndependent() {
        let a = Rng.uniform([64], seed: 1, frame: 10, stream: .dropAngle)
        let b = Rng.uniform([64], seed: 1, frame: 10, stream: .dropRadius)
        let c = Rng.uniform([64], seed: 1, frame: 11, stream: .dropAngle)
        let d = Rng.uniform([64], seed: 2, frame: 10, stream: .dropAngle)
        XCTAssertNotEqual(a.data, b.data, "two streams produced the same numbers")
        XCTAssertNotEqual(a.data, c.data, "two frames produced the same numbers")
        XCTAssertNotEqual(a.data, d.data, "two seeds produced the same numbers")
    }

    /// Element `i` is hashed on `i`, so a world draws the same numbers whatever company it is in.
    /// This is what `StepTests.testABatchOfOneMatchesTheSameWorldInsideABatchOfSixtyFour` rests on,
    /// and it is worth pinning here where a failure names the cause instead of the symptom.
    func testADrawDoesNotDependOnHowManyAreDrawnWithIt() {
        let one = Rng.uniform([1], seed: 5, frame: 2, stream: .dropLook)
        let many = Rng.uniform([256], seed: 5, frame: 2, stream: .dropLook)
        XCTAssertEqual(one[0], many[0], "world 0's draw changed when other worlds joined it")
    }

    func testScalingLandsInsideTheRange() {
        let u = Rng.uniform([512], seed: 9, frame: 1, stream: .dogTimer)
        let s = Rng.scaled(u, into: 3.5...7.25)
        for x in s.data {
            XCTAssertGreaterThanOrEqual(x, 3.5)
            XCTAssertLessThanOrEqual(x, 7.25)
        }
    }

    // MARK: - Tensor

    func testMasksAreNumbersAndWhichIsBranchless() {
        let a = Tensor(shape: [4], data: [1, 2, 3, 4])
        let b = Tensor(shape: [4], data: [4, 3, 2, 1])
        XCTAssertEqual((a .< b).data, [1, 1, 0, 0])
        XCTAssertEqual((a .>= b).data, [0, 0, 1, 1])
        XCTAssertEqual(((a .< b) .&& (a .> 1)).data, [0, 1, 0, 0])
        XCTAssertEqual((a .< b).not.data, [0, 0, 1, 1])
        XCTAssertEqual(Tensor.which(a .< b, a, b).data, [1, 2, 2, 1])
    }

    func testTheSlotAxisSpreadsAndReduces() {
        let per = Tensor(shape: [2], data: [10, 20])
        let spread = per.spread(3)
        XCTAssertEqual(spread.shape, [2, 3])
        XCTAssertEqual(spread.data, [10, 10, 10, 20, 20, 20])
        XCTAssertEqual(spread.sumSlots().data, [30, 60])
        XCTAssertEqual(spread.maxSlots().data, [10, 20])
        XCTAssertEqual(spread.minSlots().data, [10, 20])

        let slots = Tensor(shape: [2, 3], data: [5, 2, 9, 1, 7, 0])
        XCTAssertEqual(slots.argMinSlots().data, [1, 2])
        XCTAssertEqual(slots.row(1), [1, 7, 0])
    }

    /// Ties resolve to the lowest index — which is what makes "the first free slot" a deterministic
    /// choice rather than whichever one the reduction happened to visit first.
    func testArgMinPrefersTheLowestIndexOnATie() {
        let t = Tensor(shape: [1, 4], data: [0, 0, 0, 1])
        XCTAssertEqual(t.argMinSlots()[0], 0)
    }

    func testLanesAreTheSlotIndex() {
        let lanes = Tensor.lanes(batch: 2, slots: 3)
        XCTAssertEqual(lanes.shape, [2, 3])
        XCTAssertEqual(lanes.data, [0, 1, 2, 0, 1, 2])
        // Which is what makes "the first three slots" a comparison rather than a loop.
        XCTAssertEqual((lanes .< 2).data, [1, 1, 0, 1, 1, 0])
    }

    func testOneHotIsAScatter() {
        let hot = Tensor.oneHot(Tensor(shape: [2], data: [2, 0]), slots: 3)
        XCTAssertEqual(hot.data, [0, 0, 1, 1, 0, 0])
        // An out-of-range index writes nothing rather than trapping: the callers pass an argMin over
        // a possibly-empty candidate set, and "nowhere" is a legitimate answer.
        XCTAssertEqual(Tensor.oneHot(Tensor(shape: [1], data: [9]), slots: 3).data, [0, 0, 0])
    }

    func testAngleWrappingIsExactAtThePoles() {
        let t = Tensor(shape: [5], data: [0, .pi, -.pi, 3 * .pi, -3 * .pi]).wrappedToPi
        for x in t.data {
            XCTAssertLessThanOrEqual(abs(x), Double.pi + 1e-12, "\(x) is outside (−π, π]")
        }
        XCTAssertEqual(Tensor(shape: [1], data: [2 * .pi + 0.25]).wrappedToPi[0], 0.25, accuracy: 1e-12)
    }

    func testIntegerPowersAreExactMultiplications() {
        let t = Tensor(shape: [3], data: [0, 0.5, 2])
        XCTAssertEqual(t.raisedTo(0).data, [1, 1, 1])
        XCTAssertEqual(t.raisedTo(1).data, [0, 0.5, 2])
        XCTAssertEqual(t.raisedTo(3).data, [0, 0.125, 8])
    }
}
