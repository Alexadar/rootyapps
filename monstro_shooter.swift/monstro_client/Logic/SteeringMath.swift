import CoreGraphics
import Foundation

/// Pure monster-steering math extracted from `Monster.update`.
/// Supports direct steering (bugs/walkers) and arc steering (birds).
enum SteeringMath {
    struct Result {
        let position: CGPoint
        let velocity: CGVector
        let rotation: CGFloat
    }

    /// Compute one steering step toward `target`.
    /// Returns `nil` when the monster is within `stopDistance` (no movement / rotation change).
    static func step(from position: CGPoint,
                     toward target: CGPoint,
                     velocity: CGVector,
                     speed: CGFloat,
                     turnRate: CGFloat,
                     rotationOffset: CGFloat,
                     useDirectSteering: Bool,
                     stopDistance: CGFloat,
                     deltaTime: TimeInterval) -> Result? {
        let dx = target.x - position.x
        let dy = target.y - position.y
        let distance = sqrt(dx * dx + dy * dy)

        guard distance > stopDistance else { return nil }

        var vx = velocity.dx
        var vy = velocity.dy

        if useDirectSteering {
            // Direct steering (bugs, walkers) - move straight to target.
            vx = (dx / distance) * speed
            vy = (dy / distance) * speed
        } else {
            // Arc steering (birds) - smooth turning with momentum.
            vx += (turnRate * dx / distance) * CGFloat(deltaTime)
            vy += (turnRate * dy / distance) * CGFloat(deltaTime)

            // Normalize velocity and apply speed.
            let total = sqrt(vx * vx + vy * vy)
            if total > 0 {
                vx = speed * vx / total
                vy = speed * vy / total
            }
        }

        let newPos = CGPoint(x: position.x + vx * CGFloat(deltaTime),
                             y: position.y + vy * CGFloat(deltaTime))
        let angle = atan2(vy, vx)
        return Result(position: newPos,
                      velocity: CGVector(dx: vx, dy: vy),
                      rotation: angle + rotationOffset)
    }
}
