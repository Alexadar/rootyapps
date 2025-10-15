//
//  GameScene.swift
//  bigpinkcat.swift Shared
//
//  Created by Oleksandr Koreniuk on 15.10.2025.
//  Big Pink Cat - Visual Novel Game
//

import SpriteKit

class GameScene: SKScene {

    class func newGameScene() -> VisualNovelScene {
        // Create the visual novel scene
        let scene = VisualNovelScene(size: CGSize(width: 1920, height: 1080))

        // Set the scale mode to scale to fit the window
        scene.scaleMode = .aspectFill

        return scene
    }

    override func didMove(to view: SKView) {
        // This method is kept for compatibility
        // The actual game uses VisualNovelScene
    }

    override func update(_ currentTime: TimeInterval) {
        // Called before each frame is rendered
    }
}

// Input handling is done by VisualNovelScene

