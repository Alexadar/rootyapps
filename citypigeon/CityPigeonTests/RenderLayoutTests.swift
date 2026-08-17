import XCTest
import simd
@testable import CityPigeon

/// The Swift and Metal views of a shared struct must agree byte for byte.
///
/// They did not, on the first run, and the failure mode is nasty: nothing crashes, nothing warns,
/// the scene just renders in the wrong colours at the wrong sizes because every field after the
/// first is read at the wrong offset. `SIMD3<Float>` has a stride of **16** in Swift, not 12, so
/// `packed_float3` on the Metal side silently shortens the struct.
final class RenderLayoutTests: XCTestCase {

    func testInstanceLayoutMatchesTheShader() {
        // float3 + float3 + float4 + float4, all 16-byte aligned.
        XCTAssertEqual(MemoryLayout<Renderer.Instance>.stride, 64)
        XCTAssertEqual(MemoryLayout<Renderer.Instance>.alignment, 16)
    }

    func testUniformsLayoutMatchesTheShader() {
        // float4x4(64) + float3(16) + float(4)+pad + float3(16) + float(4)+pad
        XCTAssertEqual(MemoryLayout<Renderer.Uniforms>.stride, 128)
        XCTAssertEqual(MemoryLayout<Renderer.Uniforms>.alignment, 16)
    }

    /// A SIMD3 is not three floats, and forgetting that is what broke the renderer.
    func testSIMD3IsPadded() {
        XCTAssertEqual(MemoryLayout<SIMD3<Float>>.size, 16)
        XCTAssertEqual(MemoryLayout<SIMD3<Float>>.stride, 16)
    }
}
