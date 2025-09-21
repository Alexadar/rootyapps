//
//  TextureManager.swift
//  froggo.swift
//
//  Asset-only texture helper (no external paths)
//

import SpriteKit

enum TextureManager {
    /// Load texture from the asset catalog only. Returns an empty texture if not found.
    static func texture(named name: String) -> SKTexture {
        let t = SKTexture(imageNamed: name)
        return t.size() == .zero ? SKTexture() : t
    }
}
