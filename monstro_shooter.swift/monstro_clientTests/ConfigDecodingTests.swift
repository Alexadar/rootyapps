import Testing
import Foundation
@testable import monstro_client

/// These exercise the Codable decode paths of the data-driven configs.
/// We decode from JSON (Foundation only) so the tests stay hermetic and avoid the Yams dependency.
@MainActor
struct ConfigDecodingTests {
    let decoder = JSONDecoder()

    @Test func decodesWeaponConfigWithLocalization() throws {
        let json = """
        {
          "id": 4,
          "name": "Minigun",
          "type": 4,
          "nameLocalizations": { "en-us": "Minigun", "ru-ru": "Миниган" },
          "damage": 3.0,
          "shotRange": 1200,
          "shotDelay": 0.05,
          "magazineSize": 200,
          "reloadTime": 5.0,
          "bulletsPerShot": 1,
          "bulletSpeed": 900,
          "bulletDeviation": 40,
          "maxDeviation": 80,
          "penetrationPower": 1,
          "bulletStartScale": 0.3,
          "bulletMaxScale": 1.0,
          "bulletScaleGrowth": 0.05,
          "bulletTextureName": "bullet_minigun",
          "weaponSoundName": "weapon_minigun"
        }
        """
        let config = try decoder.decode(WeaponConfig.self, from: Data(json.utf8))
        #expect(config.id == 4)
        #expect(config.type == .minigun)
        #expect(config.magazineSize == 200)
        #expect(approxEqual(config.shotDelay, 0.05))
        #expect(config.getLocalizedName() == "Миниган")   // ru-ru preferred
    }

    @Test func weaponLocalizationFallsBackToName() throws {
        let json = """
        {
          "id": 1, "name": "Pistol", "type": 1,
          "damage": 5, "shotRange": 1000, "shotDelay": 0.3, "magazineSize": 12, "reloadTime": 1.5,
          "bulletsPerShot": 1, "bulletSpeed": 800, "bulletDeviation": 0, "maxDeviation": 0, "penetrationPower": 1,
          "bulletStartScale": 0.3, "bulletMaxScale": 1.0, "bulletScaleGrowth": 0.05,
          "bulletTextureName": "bullet_pistol", "weaponSoundName": "weapon_pistol"
        }
        """
        let config = try decoder.decode(WeaponConfig.self, from: Data(json.utf8))
        #expect(config.getLocalizedName() == "Pistol")   // no localizations -> base name
    }

    @Test func decodesMonsterConfigAndComputedProperties() throws {
        let json = """
        {
          "monsterTypeID": 1,
          "speed": 100,
          "boxWidth": 28,
          "boxHeight": 32,
          "damage": 5,
          "health": 10,
          "hitCooldown": 1.0,
          "rotationOffset": 0.7853981633974483,
          "useDirectSteering": true,
          "walkAnimationDirectory": "monsters/bug/walk",
          "dyingAnimationDirectory": "monsters/bug/dying",
          "walkFrameRate": 0.08,
          "dyingFrameRate": 0.06,
          "deathSounds": ["walker_1", "walker_2"]
        }
        """
        let config = try decoder.decode(MonsterConfig.self, from: Data(json.utf8))
        #expect(config.boxSize == CGSize(width: 28, height: 32))
        #expect(config.name == "Bug")                 // resolved via GameConstants.MonsterType
        #expect(config.useDirectSteering)
        #expect(config.deathSounds.count == 2)
    }

    @Test func decodesExoskeletonConfig() throws {
        let json = """
        {
          "id": 1, "name": "Standard Suit",
          "defence": 2.0, "speed": 1.0,
          "levelRequirement": 1, "rankRequirement": 0,
          "buyPriceSoft": 0, "buyPriceHard": 0, "sellPriceSoft": 0, "sellPriceHard": 0,
          "marketAvailability": true, "orderId": 1,
          "nameLocalizations": { "en-us": "Standard Suit", "ru-ru": "Стандартный костюм" }
        }
        """
        let config = try decoder.decode(ExoskeletonConfig.self, from: Data(json.utf8))
        #expect(config.id == 1)
        #expect(approxEqual(config.defence, 2.0))
        #expect(config.getLocalizedName() == "Стандартный костюм")
    }

    @Test func decodesMapConfigWithWavesAndVictims() throws {
        let json = """
        {
          "id": 14,
          "energyCost": 10,
          "landingDuration": 3,
          "gameResource": "map_background",
          "renameCost": 100,
          "renameCostMult": 2,
          "removed": false,
          "orderNumber": 1,
          "defaultNameLocalizations": { "en-us": "Outpost", "ru-ru": "Аванпост" },
          "descriptionLocalizations": { "en-us": "First map" },
          "monsterSpawnWaves": [ { "startTime": 0, "count": 5 }, { "startTime": 10, "count": 8 } ],
          "monsterTypes": [ { "startTime": 0, "monsterTypeIds": [1, 2] } ],
          "maximumVictims": { "default": 13 }
        }
        """
        let config = try decoder.decode(MapConfig.self, from: Data(json.utf8))
        #expect(config.id == 14)
        #expect(config.monsterSpawnWaves.count == 2)
        #expect(config.monsterSpawnWaves[1].count == 8)
        #expect(config.monsterTypes.first?.monsterTypeIds == [1, 2])
        #expect(config.maximumVictims["default"] == 13)
        #expect(config.getLocalizedName() == "Аванпост")
        #expect(config.ownerName == nil)   // optional missing key decodes to nil
    }

    @Test func monsterTypeRawValueResolvesName() {
        #expect(GameConstants.MonsterType(rawValue: 1)?.name == "Bug")
        #expect(GameConstants.MonsterType(rawValue: 2)?.name == "Berserker")
        #expect(GameConstants.MonsterType(rawValue: 15)?.name == "Walker")
        #expect(GameConstants.MonsterType(rawValue: 999) == nil)
    }
}
