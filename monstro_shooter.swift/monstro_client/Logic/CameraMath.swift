import CoreGraphics

/// Pure camera-follow math extracted from `WorldCamera.followTarget`.
enum CameraMath {
    /// Smoothly interpolate the camera toward `target` and clamp it so the viewport stays inside the map.
    /// When the map is smaller than the viewport on an axis, the camera centers (0) on that axis.
    static func clampedPosition(target: CGPoint,
                                current: CGPoint,
                                mapSize: CGSize,
                                viewportSize: CGSize,
                                smoothing: CGFloat) -> CGPoint {
        let targetX = current.x + (target.x - current.x) * smoothing
        let targetY = current.y + (target.y - current.y) * smoothing

        let mapMinX = -mapSize.width / 2
        let mapMaxX = mapSize.width / 2
        let mapMinY = -mapSize.height / 2
        let mapMaxY = mapSize.height / 2

        let cameraMinX = mapMinX + viewportSize.width / 2
        let cameraMaxX = mapMaxX - viewportSize.width / 2
        let cameraMinY = mapMinY + viewportSize.height / 2
        let cameraMaxY = mapMaxY - viewportSize.height / 2

        let finalX: CGFloat = mapSize.width <= viewportSize.width
            ? 0 : max(cameraMinX, min(cameraMaxX, targetX))
        let finalY: CGFloat = mapSize.height <= viewportSize.height
            ? 0 : max(cameraMinY, min(cameraMaxY, targetY))

        return CGPoint(x: finalX, y: finalY)
    }
}
