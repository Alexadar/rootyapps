import XCTest
@testable import MonstroSimGPU

final class GPUSmokeTests: XCTestCase {
    func testGPURunsAndSumsApproxHalf() {
        // Sum of 1M U(0,1) on the GPU should be ~500k.
        let s = GPUSmoke.run(n: 1_000_000)
        XCTAssertGreaterThan(s, 480_000)
        XCTAssertLessThan(s, 520_000)
    }
}
