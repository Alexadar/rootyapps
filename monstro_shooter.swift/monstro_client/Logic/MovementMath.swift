import CoreGraphics
import Foundation

/// Pure player-movement math extracted from `Player.move`.
/// Normalizes the input vector, applies the old game's 0.75 diagonal multiplier,
/// integrates by deltaTime, and clamps to map bounds (centered anchor).
enum MovementMath {
    /// Compute the player's next clamped position. Returns `position` unchanged when `movement` is zero.
    static func nextPosition(from position: CGPoint,
                             movement: CGVector,
                             speed: CGFloat,
                             deltaTime: TimeInterval,
                             spriteSize: CGSize,
                             mapSize: CGSize) -> CGPoint {
        var mv = movement
        let length = sqrt(mv.dx * mv.dx + mv.dy * mv.dy)
        guard length > 0 else { return position }

        mv.dx /= length
        mv.dy /= length

        // Match old game's 0.75 diagonal multiplier (not normalized 0.707).
        let isDiagonal = abs(mv.dx) > 0.1 && abs(mv.dy) > 0.1
        let multiplier: CGFloat = isDiagonal ? 0.75 : 1.0

        let newX = position.x + mv.dx * speed * multiplier * CGFloat(deltaTime)
        let newY = position.y + mv.dy * speed * multiplier * CGFloat(deltaTime)

        return clamp(position: CGPoint(x: newX, y: newY), spriteSize: spriteSize, mapSize: mapSize)
    }

    /// Clamp a position so the sprite stays fully inside the centered-anchor map.
    static func clamp(position: CGPoint, spriteSize: CGSize, mapSize: CGSize) -> CGPoint {
        let halfWidth = spriteSize.width / 2
        let halfHeight = spriteSize.height / 2

        let minX = -mapSize.width / 2 + halfWidth
        let maxX = mapSize.width / 2 - halfWidth
        let minY = -mapSize.height / 2 + halfHeight
        let maxY = mapSize.height / 2 - halfHeight

        return CGPoint(x: max(minX, min(maxX, position.x)),
                       y: max(minY, min(maxY, position.y)))
    }
}
