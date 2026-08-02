//
//  Skyscraper.swift
//  froggo.swift
//
//  Created by Oleksandr Koreniuk on 19.09.2025.
//

import SpriteKit

class Skyscraper: SKSpriteNode {
    var index: Int = 0
    // Tune how many times the scraper texture repeats across width/height
    private var tileMultiplierX: CGFloat = 4.0
    private var tileMultiplierY: CGFloat = 4.0
    
    init(width: CGFloat, height: CGFloat, tileX: CGFloat = 6.0, tileY: CGFloat = 6.0) {
        let texture = SKTexture(imageNamed: "scraper")
        super.init(texture: texture, color: .white, size: CGSize(width: width, height: height))
        self.tileMultiplierX = tileX
        self.tileMultiplierY = tileY
        applyTiledShader(with: texture)
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

    private func applyTiledShader(with texture: SKTexture) {
        let source = """
        void main() {
            vec2 uv = v_tex_coord * u_textureScale;
            uv = fract(uv);
            gl_FragColor = texture2D(u_texture, uv) * v_color_mix;
        }
        """
        let shader = SKShader(source: source)
        let scaleX = max(1.0, Float((size.width / texture.size().width) * tileMultiplierX))
        let scaleY = max(1.0, Float((size.height / texture.size().height) * tileMultiplierY))
        let uniform = SKUniform(name: "u_textureScale", vectorFloat2: vector_float2(scaleX, scaleY))
        shader.uniforms = [uniform]
        self.shader = shader
    }
}
