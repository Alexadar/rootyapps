import Foundation
import MLX
import Metal

// Phase-0 spike for the Metal-canonical unification: can a raw Metal compute kernel mutate an
// MLX array's backing buffer IN PLACE (via asMTLBuffer noCopy) and have MLX see the result?
// If yes, the canonical Metal kinetics kernels can drive the MLX training state directly — one
// source of truth shared by the game and the trainer.
public enum MetalBridgeSpike {
    public static func run() -> String {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            return "FAIL: no Metal device"
        }
        let n = 4096
        let a = MLXArray(Array(repeating: Float(1.0), count: n), [n])   // all 1.0
        eval(a)

        guard let buf = a.asMTLBuffer(device: device, noCopy: true) else {
            return "noCopy=nil — MLX buffer not bytesNoCopy-able (alignment). Fallback: MLXFast.metalKernel."
        }

        let src = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void addone(device float* x [[buffer(0)]], constant uint& n [[buffer(1)]],
                           uint id [[thread_position_in_grid]]) { if (id < n) x[id] += 1.0f; }
        """
        guard let lib = try? device.makeLibrary(source: src, options: nil),
              let fn = lib.makeFunction(name: "addone"),
              let pso = try? device.makeComputePipelineState(function: fn) else {
            return "FAIL: kernel compile"
        }
        let cmd = queue.makeCommandBuffer()!
        let e = cmd.makeComputeCommandEncoder()!
        e.setComputePipelineState(pso)
        e.setBuffer(buf, offset: 0, index: 0)
        var nn = UInt32(n); e.setBytes(&nn, length: 4, index: 1)
        e.dispatchThreads(MTLSize(width: n, height: 1, depth: 1),
                          threadsPerThreadgroup: MTLSize(width: min(pso.maxTotalThreadsPerThreadgroup, 256), height: 1, depth: 1))
        e.endEncoding(); cmd.commit(); cmd.waitUntilCompleted()

        // Did the in-place mutation persist into the MLX array?
        let host = a.asArray(Float.self)
        let persisted = host.allSatisfy { abs($0 - 2.0) < 1e-4 }
        // Does a subsequent MLX op see the new values?
        let s = a.sum(); eval(s)
        let total = s.item(Float.self)
        let mlxSees = abs(total - Float(2 * n)) < 1.0

        return persisted && mlxSees
            ? "PASS: raw Metal mutated MLX buffer in-place (host[0]=\(host[0]), MLX sum=\(total)==\(2*n)). Bridge works."
            : "PARTIAL: persisted=\(persisted) host[0]=\(host[0]); mlxSees=\(mlxSees) sum=\(total). Investigate."
    }
}
