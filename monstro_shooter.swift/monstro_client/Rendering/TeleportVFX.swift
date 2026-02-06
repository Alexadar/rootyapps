import SpriteKit

/// Teleport in/out visual effects for player
/// Creates a sci-fi beam/ring effect with converging/diverging particles
class TeleportVFX {

    static let duration: TimeInterval = 0.5

    /// Teleport IN — player materializes with converging ring + flash
    /// Player sprite should be hidden before calling. It will be shown during animation.
    static func teleportIn(node: SKNode, at position: CGPoint, in parent: SKNode, completion: @escaping () -> Void) {
        // Start player invisible and tiny
        node.alpha = 0
        node.setScale(0.01)
        node.position = position

        // Container for VFX (added to same parent as player)
        let vfxContainer = SKNode()
        vfxContainer.position = position
        vfxContainer.zPosition = node.zPosition + 1
        parent.addChild(vfxContainer)

        // 1. Beam pillar — vertical light column
        let beam = SKSpriteNode(color: .cyan, size: CGSize(width: 8, height: 300))
        beam.alpha = 0
        beam.setScale(1)
        beam.zPosition = -1
        vfxContainer.addChild(beam)

        let beamIn = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.7, duration: 0.1),
            SKAction.wait(forDuration: 0.25),
            SKAction.fadeOut(withDuration: 0.15)
        ])
        beam.run(beamIn)

        // 2. Ring — expanding circle that contracts
        let ring = SKShapeNode(circleOfRadius: 40)
        ring.strokeColor = .cyan
        ring.fillColor = .clear
        ring.lineWidth = 3
        ring.alpha = 0
        ring.setScale(3.0)
        ring.glowWidth = 4
        vfxContainer.addChild(ring)

        let ringAnim = SKAction.group([
            SKAction.fadeAlpha(to: 0.9, duration: 0.15),
            SKAction.sequence([
                SKAction.scale(to: 0.3, duration: 0.35),
                SKAction.group([
                    SKAction.scale(to: 0.01, duration: 0.15),
                    SKAction.fadeOut(withDuration: 0.15)
                ])
            ])
        ])
        ring.run(ringAnim)

        // 3. Converging particles — 8 dots spiral inward
        let particleCount = 8
        for i in 0..<particleCount {
            let angle = CGFloat(i) / CGFloat(particleCount) * .pi * 2
            let radius: CGFloat = 120
            let startX = cos(angle) * radius
            let startY = sin(angle) * radius

            let particle = SKShapeNode(circleOfRadius: 3)
            particle.fillColor = .white
            particle.strokeColor = .cyan
            particle.lineWidth = 1
            particle.glowWidth = 2
            particle.position = CGPoint(x: startX, y: startY)
            particle.alpha = 0
            vfxContainer.addChild(particle)

            let delay = Double(i) * 0.03
            let particleAnim = SKAction.sequence([
                SKAction.wait(forDuration: delay),
                SKAction.fadeAlpha(to: 1.0, duration: 0.05),
                SKAction.group([
                    SKAction.move(to: .zero, duration: 0.35),
                    SKAction.rotate(byAngle: .pi, duration: 0.35),
                    SKAction.sequence([
                        SKAction.wait(forDuration: 0.25),
                        SKAction.fadeOut(withDuration: 0.1)
                    ])
                ])
            ])
            particle.run(particleAnim)
        }

        // 4. Center flash
        let flash = SKShapeNode(circleOfRadius: 20)
        flash.fillColor = .white
        flash.strokeColor = .clear
        flash.alpha = 0
        flash.setScale(0.1)
        vfxContainer.addChild(flash)

        let flashAnim = SKAction.sequence([
            SKAction.wait(forDuration: 0.3),
            SKAction.group([
                SKAction.fadeAlpha(to: 0.8, duration: 0.05),
                SKAction.scale(to: 2.0, duration: 0.15)
            ]),
            SKAction.fadeOut(withDuration: 0.1)
        ])
        flash.run(flashAnim)

        // 5. Player materializes
        let playerAnim = SKAction.sequence([
            SKAction.wait(forDuration: 0.15),
            SKAction.group([
                SKAction.fadeIn(withDuration: 0.25),
                SKAction.scale(to: 1.0, duration: 0.3)
            ])
        ])

        node.run(playerAnim)

        // Cleanup after total duration
        let cleanup = SKAction.sequence([
            SKAction.wait(forDuration: duration),
            SKAction.removeFromParent()
        ])
        vfxContainer.run(cleanup) {
            completion()
        }
    }

    /// Teleport OUT — player dematerializes with expanding ring + flash
    /// Player sprite will be hidden after animation.
    static func teleportOut(node: SKNode, in parent: SKNode, completion: @escaping () -> Void) {
        let position = node.position

        // Container for VFX
        let vfxContainer = SKNode()
        vfxContainer.position = position
        vfxContainer.zPosition = node.zPosition + 1
        parent.addChild(vfxContainer)

        // 1. Center flash first
        let flash = SKShapeNode(circleOfRadius: 20)
        flash.fillColor = .white
        flash.strokeColor = .clear
        flash.alpha = 0
        flash.setScale(0.1)
        vfxContainer.addChild(flash)

        let flashAnim = SKAction.sequence([
            SKAction.group([
                SKAction.fadeAlpha(to: 0.9, duration: 0.05),
                SKAction.scale(to: 1.5, duration: 0.1)
            ]),
            SKAction.fadeOut(withDuration: 0.15)
        ])
        flash.run(flashAnim)

        // 2. Ring — expands outward
        let ring = SKShapeNode(circleOfRadius: 40)
        ring.strokeColor = .cyan
        ring.fillColor = .clear
        ring.lineWidth = 3
        ring.alpha = 0
        ring.setScale(0.1)
        ring.glowWidth = 4
        vfxContainer.addChild(ring)

        let ringAnim = SKAction.group([
            SKAction.fadeAlpha(to: 0.9, duration: 0.1),
            SKAction.sequence([
                SKAction.scale(to: 2.5, duration: 0.35),
                SKAction.fadeOut(withDuration: 0.15)
            ])
        ])
        ring.run(ringAnim)

        // 3. Diverging particles — 8 dots fly outward
        let particleCount = 8
        for i in 0..<particleCount {
            let angle = CGFloat(i) / CGFloat(particleCount) * .pi * 2
            let radius: CGFloat = 120
            let endX = cos(angle) * radius
            let endY = sin(angle) * radius

            let particle = SKShapeNode(circleOfRadius: 3)
            particle.fillColor = .white
            particle.strokeColor = .cyan
            particle.lineWidth = 1
            particle.glowWidth = 2
            particle.position = .zero
            particle.alpha = 0
            vfxContainer.addChild(particle)

            let delay = Double(i) * 0.02
            let particleAnim = SKAction.sequence([
                SKAction.wait(forDuration: delay + 0.05),
                SKAction.fadeAlpha(to: 1.0, duration: 0.05),
                SKAction.group([
                    SKAction.move(to: CGPoint(x: endX, y: endY), duration: 0.3),
                    SKAction.rotate(byAngle: -.pi, duration: 0.3),
                    SKAction.sequence([
                        SKAction.wait(forDuration: 0.15),
                        SKAction.fadeOut(withDuration: 0.15)
                    ])
                ])
            ])
            particle.run(particleAnim)
        }

        // 4. Beam pillar fades in then out
        let beam = SKSpriteNode(color: .cyan, size: CGSize(width: 8, height: 300))
        beam.alpha = 0
        beam.zPosition = -1
        vfxContainer.addChild(beam)

        let beamAnim = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.6, duration: 0.1),
            SKAction.wait(forDuration: 0.15),
            SKAction.fadeOut(withDuration: 0.2)
        ])
        beam.run(beamAnim)

        // 5. Player dematerializes
        let playerAnim = SKAction.group([
            SKAction.fadeOut(withDuration: 0.25),
            SKAction.scale(to: 0.01, duration: 0.3)
        ])

        node.run(playerAnim)

        // Cleanup
        let cleanup = SKAction.sequence([
            SKAction.wait(forDuration: duration),
            SKAction.removeFromParent()
        ])
        vfxContainer.run(cleanup) {
            completion()
        }
    }
}
