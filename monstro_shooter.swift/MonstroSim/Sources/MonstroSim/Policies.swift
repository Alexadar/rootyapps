import Foundation

public protocol Policy {
    func act(_ world: World) -> SimAction
}

// MARK: - Direction helpers
enum Dir {
    /// Nearest of the 8 compass move directions for a desired vector (0 = idle).
    static func moveDir(for v: Vec2) -> Int {
        if v.length < 1e-6 { return 0 }
        let target = atan2(v.y, v.x)
        var best = 0; var bestDiff = Double.greatestFiniteMagnitude
        for dir in 1...8 {
            let mv = SimAction.moveVector(dir)
            let diff = abs(angleDiff(atan2(mv.y, mv.x), target))
            if diff < bestDiff { bestDiff = diff; best = dir }
        }
        return best
    }

    static func aimDir(for angle: Double) -> Int {
        var a = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if a < 0 { a += 2 * .pi }
        return Int((a / (2 * .pi) * Double(SimAction.aimDirs)).rounded()) % SimAction.aimDirs
    }

    static func angleDiff(_ a: Double, _ b: Double) -> Double {
        var d = a - b
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        return d
    }
}

// MARK: - Random baseline
public final class RandomPolicy: Policy {
    private var rng: SeededGenerator
    public init(seed: UInt64) { self.rng = SeededGenerator(seed: seed) }
    public func act(_ world: World) -> SimAction {
        SimAction(moveDir: Int.random(in: 0..<SimAction.moveDirs, using: &rng),
                  aimDir: Int.random(in: 0..<SimAction.aimDirs, using: &rng),
                  shoot: Bool.random(using: &rng))
    }
}

// MARK: - Idle (stand still, shoot nearest) — a deliberately weak agent
public struct IdlePolicy: Policy {
    public init() {}
    public func act(_ world: World) -> SimAction {
        guard let near = nearest(world) else { return SimAction() }
        let aim = (near.pos - world.player.pos).angle
        return SimAction(moveDir: 0, aimDir: Dir.aimDir(for: aim), shoot: true)
    }
    func nearest(_ w: World) -> SimMonster? {
        w.monsters.filter { !$0.isDead }.min { $0.pos.distance(to: w.player.pos) < $1.pos.distance(to: w.player.pos) }
    }
}

// MARK: - Kiter (aim+shoot nearest, retreat from nearby cluster) — scripted difficulty baseline
public struct KiterPolicy: Policy {
    public var threatRadius: Double
    public init(threatRadius: Double = 350) { self.threatRadius = threatRadius }

    public func act(_ world: World) -> SimAction {
        let p = world.player.pos
        let alive = world.monsters.filter { !$0.isDead }
        guard let nearest = alive.min(by: { $0.pos.distance(to: p) < $1.pos.distance(to: p) }) else {
            return SimAction(moveDir: 0, aimDir: 0, shoot: false)
        }
        // Aim at nearest, always shoot.
        let aim = (nearest.pos - p).angle

        // Retreat from the centroid of monsters within threatRadius.
        var away = Vec2.zero
        var count = 0
        for m in alive where m.pos.distance(to: p) < threatRadius {
            let d = p - m.pos
            let l = d.length
            if l > 0 { away = away + Vec2(d.x / l, d.y / l) * (1.0 / max(l, 1)); count += 1 }
        }
        let moveDir = count > 0 ? Dir.moveDir(for: away) : 0
        return SimAction(moveDir: moveDir, aimDir: Dir.aimDir(for: aim), shoot: true)
    }
}
