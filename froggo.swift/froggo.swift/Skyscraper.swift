//
//  Skyscraper.swift
//  froggo.swift
//
//  Created by Oleksandr Koreniuk on 19.09.2025.
//

import SpriteKit

class Skyscraper: SKSpriteNode {
    var index: Int = 0
    
    init(width: CGFloat, height: CGFloat) {
    let texture = SKTexture(imageNamed: "scraper")
        super.init(texture: texture, color: .gray, size: CGSize(width: width, height: height))
    // Attempt to reduce edge stretching by using centerRect (9-slice). Assumes texture has margins.
    self.centerRect = CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1)
        
        setupPhysics()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupPhysics() {
        physicsBody = SKPhysicsBody(rectangleOf: size)
        physicsBody?.categoryBitMask = PhysicsCategory.skyscraper
        physicsBody?.contactTestBitMask = PhysicsCategory.frog
        physicsBody?.collisionBitMask = PhysicsCategory.frog
        physicsBody?.isDynamic = false // Skyscrapers don't move
        physicsBody?.friction = 0.8
        physicsBody?.restitution = 0.2
    }
}
