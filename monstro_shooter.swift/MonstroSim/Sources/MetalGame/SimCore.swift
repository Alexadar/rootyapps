import Foundation
import MLX

// Shared sim types: the WorldConfig + per-game schedule JSON (exported by torchsim), the deterministic
// spread hash, the in-graph MLP, and the parity-dump records. One batched sim (BatchSim/GridSim) consumes
// all of these — there is no separate single-game engine.

struct WorldJSON: Codable {
    var dt, player_speed, player_half, player_radius, map_half, turn_rate, buffer, bullet_radius: Float
    var damage_interval, diagonal_factor, defense_min_floor, player_max_hp, dist_norm: Float
    var monster_speed_norm, monster_count_norm, bullet_norm, eps: Float
}

struct SchedJSON: Codable {
    var name: String, gid: String, M: Int, B: Int, ticks: Int, arena_half: Float
    var spawn_tick: [Float], offset: [[Float]], hp0: [Float], speed: [Float]
    var boxW: [Float], dmg: [Float], direct: [Float], type: [Int]
    var bullet_speed, bullet_damage, bullet_range: Float
    var fire_interval, contact_interval: Int, defense: Float
    var bullets_per_shot, penetration, mag_size, reload_ticks: Int
    var max_dev, exo_speed: Float
}

/// In-graph MLP from the shared {sizes,w,b} JSON (same file Core ML exports from). Weights [in,out], relu
/// on hidden layers, linear out — mirrors torchsim/policy_torch.py::apply_mlp. Batched: an [N,M,in] (or
/// [N,in]) input runs every row in one matmul.
final class MLXMLP {
    struct NetJSON: Codable { var sizes: [Int]; var w: [[Float]]; var b: [[Float]] }
    private var W: [MLXArray] = []
    private var bias: [MLXArray] = []
    init?(path: String) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let d = try? JSONDecoder().decode(NetJSON.self, from: data) else { return nil }
        for i in 0..<d.w.count {
            W.append(MLXArray(d.w[i], [d.sizes[i], d.sizes[i + 1]]))
            bias.append(MLXArray(d.b[i], [d.sizes[i + 1]]))
        }
    }
    func callAsFunction(_ x: MLXArray) -> MLXArray {
        var h = x
        let n = W.count
        for i in 0..<n {                       // MLP-depth loop (network layers, not entities)
            h = matmul(h, W[i]) + bias[i]
            if i < n - 1 { h = maximum(h, MLXArray(0.0)) }
        }
        return h
    }
}

// ---- parity-dump records (one trajectory per game, diffed against torch by parity_diff.py) ----
struct IndexJSON: Codable { var games: [String]; var bullets: Int }
struct FrameOut: Codable {
    var t: Int; var player: [Float]; var mon_alive: [Int]; var mon_pos: [Float]
    var bul_alive: [Int]; var bul_pos: [Float]; var kills: Int; var hp: Float
}
