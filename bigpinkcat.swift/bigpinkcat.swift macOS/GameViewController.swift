//
//  GameViewController.swift
//  bigpinkcat.swift macOS
//
//  Created by Oleksandr Koreniuk on 15.10.2025.
//

import Cocoa
import SpriteKit
import GameplayKit

class GameViewController: NSViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Present VisualNovelScene sized to the view; use resizeFill for dynamic scaling
        let skView = self.view as! SKView
        let scene = VisualNovelScene(size: skView.bounds.size)
        scene.scaleMode = .resizeFill
        skView.presentScene(scene)
        
        skView.ignoresSiblingOrder = true
        
        skView.showsFPS = true
        skView.showsNodeCount = true
    }

}
