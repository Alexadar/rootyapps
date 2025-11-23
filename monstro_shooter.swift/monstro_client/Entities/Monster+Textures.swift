import Foundation
import SpriteKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Texture Loading Utilities
extension Monster {

    /// Load textures from sprite atlas in Assets.xcassets
    /// Atlas names: Bug/Walk, Bug/Dying, Berserker/Walk, etc.
    /// Expects subpath like "monsters/bug/walk" -> loads from "Bug/Walk" atlas
    /// Textures named: walk_01.png, walk_02.png or dying_01.png, dying_02.png
    func loadTextures(fromDirectory subpath: String) -> [SKTexture] {
        var textures: [SKTexture] = []

        // Parse subpath to get atlas name
        // "monsters/bug/walk" -> "Bug/Walk"
        let components = subpath.components(separatedBy: "/")
        guard components.count >= 3 else {
            print("[Monster+Textures] ERROR: Invalid subpath format: \(subpath)")
            return textures
        }

        let monsterType = components[components.count - 2]  // "bug", "bird", "berserker", etc.
        let animType = components[components.count - 1]     // "walk", "dying"

        // Nested atlas name with namespace: "monsters/berserker/walk" -> "Berserker/Walk"
        let atlasName = "\(monsterType.capitalized)/\(animType.capitalized)"

        print("[Monster+Textures] Loading atlas: \(atlasName) from subpath: \(subpath)")

        // Load atlas
        let atlas = SKTextureAtlas(named: atlasName)
        let textureNames = atlas.textureNames

        print("[Monster+Textures] Atlas '\(atlasName)' has \(textureNames.count) textures: \(textureNames.prefix(5))")

        // Filter textures by animation type prefix (walk_ or dying_)
        let prefix = "\(monsterType.capitalized)/\(animType)_"
        let filteredNames = textureNames.filter { $0.hasPrefix(prefix) }

        print("[Monster+Textures] Filtered \(filteredNames.count) textures with prefix '\(prefix)'")

        // IMPORTANT: Use .last not .first to extract frame number!
        // "Bird5/dying_01" splits to [5, 1] - .first returns 5 (monster ID), .last returns 1 (frame)
        // Using .first caused all frames to have same sort key = random order = glitchy animations
        let sortedNames = filteredNames.sorted { (a, b) -> Bool in
            let numA = a.components(separatedBy: CharacterSet.decimalDigits.inverted)
                .compactMap { Int($0) }
                .last ?? 0  // .last = frame number, NOT .first
            let numB = b.components(separatedBy: CharacterSet.decimalDigits.inverted)
                .compactMap { Int($0) }
                .last ?? 0
            return numA < numB
        }

        for textureName in sortedNames {
            let texture = atlas.textureNamed(textureName)
            textures.append(texture)
        }

        print("[Monster+Textures] Loaded \(textures.count) textures from atlas '\(atlasName)'")

        return textures
    }
}
