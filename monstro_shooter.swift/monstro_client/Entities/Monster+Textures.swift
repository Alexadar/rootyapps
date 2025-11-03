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
    /// Atlas names: bug_walk, bug_dying, bug2_walk, etc.
    /// Expects subpath like "monsters/bug/walk" -> loads from "bug_walk" atlas
    func loadTextures(fromDirectory subpath: String) -> [SKTexture] {
        var textures: [SKTexture] = []

        // Parse subpath to get atlas name
        // "monsters/bug/walk" -> "Bug/Walk"
        let components = subpath.components(separatedBy: "/")
        guard components.count >= 3 else {
            print("[Monster+Textures] ERROR: Invalid subpath format: \(subpath)")
            return textures
        }

        let monsterType = components[components.count - 2]  // "bug", "bird", etc.
        let animType = components[components.count - 1]     // "walk", "dying"

        // Nested atlas name with namespace: "bug/walk" -> "Berserker/Walk"
        let atlasName = "\(monsterType.capitalized)/\(animType.capitalized)"

        print("[Monster+Textures] Loading atlas: \(atlasName) from subpath: \(subpath)")

        // Load atlas
        let atlas = SKTextureAtlas(named: atlasName)
        let textureNames = atlas.textureNames

        print("[Monster+Textures] Atlas '\(atlasName)' has \(textureNames.count) textures: \(textureNames.prefix(5))")

        let sortedNames = textureNames.sorted { (a, b) -> Bool in
            // Extract numeric part from filename (e.g., "12.png" -> 12, "12" -> 12)
            let numA = a.components(separatedBy: CharacterSet.decimalDigits.inverted)
                .compactMap { Int($0) }
                .first ?? 0
            let numB = b.components(separatedBy: CharacterSet.decimalDigits.inverted)
                .compactMap { Int($0) }
                .first ?? 0

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
