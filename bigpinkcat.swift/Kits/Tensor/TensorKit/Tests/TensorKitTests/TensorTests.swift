import XCTest
@testable import TensorKit

/// ORACLES: shape algebra and the elementwise laws are *definitions*, cross-checked numerically
/// (the **Identity** class in `docs/calculators_VALIDATION.md`). `matmul4x4` is checked against a
/// hand-computed reference, which is an independent implementation.
final class TensorTests: XCTestCase {

    func testShapeMustDescribeTheData() {
        XCTAssertEqual(Tensor(shape: [2, 3], data: Array(repeating: 0, count: 6)).count, 6)
    }

    func testElementwiseOpsPreserveShape() {
        let a = Tensor(shape: [2, 3], data: [1, 2, 3, 4, 5, 6])
        let b = Tensor(shape: [2, 3], data: [6, 5, 4, 3, 2, 1])
        XCTAssertEqual((a + b).data, [7, 7, 7, 7, 7, 7])
        XCTAssertEqual((a * b).data, [6, 10, 12, 12, 10, 6])
        XCTAssertEqual((a + b).shape, [2, 3])
    }

    func testMasksAreNumbersNotBooleans() {
        // The property the whole branchless design rests on: a conditional is a multiply.
        let a = Tensor(shape: [4], data: [1, 5, 3, 9])
        XCTAssertEqual((a .> 3.0).data, [0, 1, 0, 1])
        XCTAssertEqual((a .> 3.0).not.data, [1, 0, 1, 0])
        XCTAssertEqual(Tensor.which(a .> 3.0, a, 0.0).data, [0, 5, 0, 9])
    }

    func testNewlySetIsTrueEdgeDetection() {
        // now·(1−previous): fires only on the rising edge, never while already set.
        let now =  Tensor(shape: [4], data: [0, 1, 1, 0])
        let prev = Tensor(shape: [4], data: [0, 0, 1, 1])
        XCTAssertEqual(Tensor.newlySet(now: now, previous: prev).data, [0, 1, 0, 0])
    }

    func testUnstackStackRoundTrips() {
        // The geodesic state plumbing. If this is lossy, every trajectory is quietly wrong.
        let y = Tensor(shape: [3, 8], data: (0..<24).map(Double.init))
        let parts = y.unstackLast()
        XCTAssertEqual(parts.count, 8)
        XCTAssertEqual(parts[0].shape, [3])
        XCTAssertEqual(parts[1].data, [1, 9, 17])
        XCTAssertEqual(Tensor.stackLast(parts).data, y.data, "round trip is exact")
        XCTAssertEqual(Tensor.stackLast(parts).shape, y.shape)
    }

    func testExpandedRowsAndColumnsTouchEveryOrderedPair() {
        let v = Tensor(shape: [1, 3], data: [10, 20, 30])
        XCTAssertEqual(v.expandedAsRows().data, [10, 10, 10, 20, 20, 20, 30, 30, 30])
        XCTAssertEqual(v.expandedAsColumns().data, [10, 20, 30, 10, 20, 30, 10, 20, 30])
    }

    func testOffDiagonalExcludesSelfPairs() {
        let d = Tensor.offDiagonal(worlds: 1, slots: 3)
        XCTAssertEqual(d.data, [0, 1, 1, 1, 0, 1, 1, 1, 0])
    }

    func testReductions() {
        let t = Tensor(shape: [2, 3], data: [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(t.sumLast().data, [6, 15])
        XCTAssertEqual(t.maxLast().data, [3, 6])
        XCTAssertEqual(t.sumLast().shape, [2])
    }

    func testMinLastFiniteIgnoresInfinities() {
        // Non-finite means "no solution" and must not win a minimum.
        let t = Tensor(shape: [1, 4], data: [.infinity, 7, .nan, 3])
        XCTAssertEqual(t.minLastFinite().data, [3])
    }

    func testAnyOverSourcesIsTheFloodFillStep() {
        // next[j] = OR over i of adjacency[i][j]. Repeating this K times floods a graph with no
        // queue and no per-node loop.
        let adj = Tensor(shape: [1, 3, 3], data: [0, 1, 0,
                                                  0, 0, 1,
                                                  0, 0, 0])
        XCTAssertEqual(adj.anyOverSources().data, [0, 1, 1])
    }

    // MARK: - Batched 4×4

    func testMatmulAgainstAHandComputedReference() {
        // Independent implementation: worked by hand, not by running the code.
        // [[1,2,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]] · [[1,0,0,3],[0,1,0,4],[0,0,1,0],[0,0,0,1]]
        //   = [[1,2,0,11],[0,1,0,4],[0,0,1,0],[0,0,0,1]]
        let a = Tensor(shape: [1, 4, 4], data: [1, 2, 0, 0,
                                                0, 1, 0, 0,
                                                0, 0, 1, 0,
                                                0, 0, 0, 1])
        let b = Tensor(shape: [1, 4, 4], data: [1, 0, 0, 3,
                                                0, 1, 0, 4,
                                                0, 0, 1, 0,
                                                0, 0, 0, 1])
        XCTAssertEqual(Tensor.matmul4x4(a, b).data, [1, 2, 0, 11,
                                                     0, 1, 0, 4,
                                                     0, 0, 1, 0,
                                                     0, 0, 0, 1])
    }

    func testIdentityIsAMultiplicativeIdentity() {
        let i = Tensor.identity4x4(batches: [2])
        let m = Tensor(shape: [2, 4, 4], data: (0..<32).map { Double($0) * 0.25 })
        XCTAssertEqual(Tensor.matmul4x4(i, m).data, m.data)
        XCTAssertEqual(Tensor.matmul4x4(m, i).data, m.data)
    }

    func testApply4x4TranslatesAHomogeneousPoint() {
        let t = Tensor(shape: [1, 4, 4], data: [1, 0, 0, 5,
                                                0, 1, 0, -2,
                                                0, 0, 1, 7,
                                                0, 0, 0, 1])
        let p = Tensor(shape: [1, 4], data: [1, 1, 1, 1])
        XCTAssertEqual(Tensor.apply4x4(t, to: p).data, [6, -1, 8, 1])
    }

    // MARK: - Deterministic trig, via the vector face

    func testVectorTrigMatchesTheScalarKernel() {
        // The vector API is the interface; the scalar is a kernel. They must not diverge, because
        // domain code only ever sees the former while the tests of the latter are what prove it.
        let t = Tensor(shape: [5], data: [0, 0.5, 1.0, -2.0, 3.0])
        for (i, v) in t.sin.data.enumerated() {
            XCTAssertEqual(v, DetMathScalarSin(t.data[i]), accuracy: 0)
        }
    }

    func testPythagoreanIdentityHoldsElementwise() {
        let t = Tensor(shape: [64], data: (0..<64).map { Double($0) * 0.19 - 6 })
        let s = t.sin, c = t.cos
        for v in (s * s + c * c).data {
            XCTAssertEqual(v, 1.0, accuracy: 1e-14)
        }
    }

    // MARK: - The batch-of-one law

    func testBatchOfOneEqualsAnElementOfABatch() {
        // The single most load-bearing property in the architecture: N = 1 and N = many are the
        // same code, so every scalar test is also a test of the vector path. If this ever fails,
        // the batching is a second implementation and half the oracles cover nothing.
        let values = [0.3, 1.7, -2.2, 5.0]
        let batch = Tensor(shape: [values.count], data: values).sin
        for (i, v) in values.enumerated() {
            let single = Tensor(shape: [1], data: [v]).sin
            XCTAssertEqual(batch.data[i], single.data[0], accuracy: 0,
                           "batched sin must be bit-identical to batch-of-one at \(v)")
        }
    }
}

/// Reaches the scalar kernel deliberately, which is exactly what domain code may not do.
private func DetMathScalarSin(_ x: Double) -> Double {
    Tensor(shape: [1], data: [x]).sin.data[0]
}
