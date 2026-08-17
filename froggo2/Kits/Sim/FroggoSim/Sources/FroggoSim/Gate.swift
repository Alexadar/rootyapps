import Foundation
import MLX
import ReachabilityKit

/// Day-1 viability gate for the mlx-swift dependency: does the batched program's core vocabulary
/// exist and compile on this SDK? Everything the real sim needs is exercised here once, so a missing
/// API is found in minutes rather than after the architecture is committed to.
public enum Gate {
    public static func smoke() -> [Float] {
        let n = 4, k = 6

        // [N,K] roof heights and an alive mask — the shape everything else broadcasts against.
        let heights = MLXArray(converting: (0..<(n * k)).map { Double($0) }).reshaped([n, k])
        let alive = MLXArray.ones([n, k])

        // [N,K,K] pairwise rise: the outer product that replaces the double loop.
        let rise = heights.expandedDimensions(axis: 1) - heights.expandedDimensions(axis: 2)

        // Masked comparison -> adjacency, then "does every roof reach something" as a reduction.
        let adj = MLX.which(rise .< 3.0, MLXArray(1.0), MLXArray(0.0)) * alive.expandedDimensions(axis: 1)
        let outDegree = adj.sum(axis: 2)

        // One boolean BFS relaxation: adj @ frontier. K of these is the whole route search.
        let frontier = MLXArray.zeros([n, k, 1])
        let next = MLX.matmul(adj, frontier)

        let result = outDegree + next.squeezed(axis: 2)
        result.eval()
        return result.asArray(Float.self)
    }

    /// Proves the two Kits link together and the constants come from one place.
    public static var config: WorldConfig { .shipping }
}
