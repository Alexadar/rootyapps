import XCTest
import TarotKit
@testable import Tarot

/// The audio policy and the method/deck/skin abstractions. The AVAudioEngine layer itself
/// stays untested (a dumb executor, like the renderer); what's tested is every decision —
/// and every toggle in BOTH directions (the dead-toggle rule: a wired-but-ignored setting
/// has shipped in this repo before).
final class AudioAndSkinChecks: XCTestCase {

    // MARK: Music policy

    func testMusicVolumeFollowsToggleAndScenePhase() {
        XCTAssertEqual(AudioPlan.targetMusicVolume(musicEnabled: true, isActive: true),
                       AudioPlan.musicLevel)
        XCTAssertEqual(AudioPlan.targetMusicVolume(musicEnabled: false, isActive: true), 0)
        XCTAssertEqual(AudioPlan.targetMusicVolume(musicEnabled: true, isActive: false), 0)
        XCTAssertEqual(AudioPlan.targetMusicVolume(musicEnabled: false, isActive: false), 0)
        XCTAssertGreaterThan(AudioPlan.musicLevel, 0)
    }

    /// Every sound the code can ask for must exist in the built app bundle — a missing
    /// resource fails silently at runtime (the controller just skips it), so THIS is the
    /// place that failure becomes loud. The test host is the real Tarot.app.
    func testEverySoundResourceIsBundled() {
        for sound in GameSound.allCases {
            XCTAssertNotNil(Bundle.main.url(forResource: sound.rawValue, withExtension: "caf"),
                            "missing \(sound.rawValue).caf in the app bundle")
            XCTAssertGreaterThan(sound.gain, 0)
            XCTAssertLessThanOrEqual(sound.gain, 1)
        }
        // BGM is parked: the bed must be bundled exactly when the feature flag says so —
        // a stale 1.4 MB m4a shipping with the flag off is also a failure.
        XCTAssertEqual(Bundle.main.url(forResource: "bgm_arcana", withExtension: "m4a") != nil,
                       AppModel.musicFeatureEnabled,
                       "bgm_arcana.m4a bundling must match AppModel.musicFeatureEnabled")
    }

    // MARK: Interpretations gate

    func testWriterOnlyRunsWhenEnabledAndAvailable() {
        XCTAssertTrue(AppModel.shouldWrite(interpretationsEnabled: true, availability: .available))
        XCTAssertFalse(AppModel.shouldWrite(interpretationsEnabled: false, availability: .available))
        XCTAssertFalse(AppModel.shouldWrite(interpretationsEnabled: true, availability: .deviceNotEligible))
        XCTAssertFalse(AppModel.shouldWrite(interpretationsEnabled: true, availability: .notEnabled))
        XCTAssertFalse(AppModel.shouldWrite(interpretationsEnabled: true, availability: .modelNotReady))
        XCTAssertFalse(AppModel.shouldWrite(interpretationsEnabled: false, availability: .modelNotReady))
    }

    // MARK: Method / Deck / Skin

    func testMethodIsTheSpreadByItsProperName() {
        // The typealias is the abstraction the owner named; if Method ever drifts from
        // Spread this stops compiling, which is the point.
        let method: TarotKit.Method = .threeCard   // qualified: ObjC runtime also has a `Method`
        XCTAssertEqual(method.id, "three-card")
        XCTAssertEqual(method.positions.count, 3)
    }

    @MainActor
    func testDefaultSkinIsMidnightAndRegistered() {
        XCTAssertEqual(Skins.standard.id, "midnight")
        XCTAssertTrue(Skins.all.contains { $0.id == Skins.standard.id })
        XCTAssertEqual(SkinnedArtProvider().skin.id, Skins.standard.id)
    }

    @MainActor
    func testSkinnedFacesRenderAndCache() {
        let provider = SkinnedArtProvider()
        let major = provider.art(for: .major(6), deck: .classic1909)
        let minor = provider.art(for: .minor(.cups, .seven), deck: .classic1909)
        XCTAssertTrue(major.isMajor)
        XCTAssertFalse(minor.isMajor)
        XCTAssertEqual(major.face.width, 512)
        XCTAssertEqual(major.face.height, 880)
        // Cache: the same card must come back as the same image object — but the SAME
        // structural card under a DIFFERENT deck is different art (different name on it).
        XCTAssertTrue(provider.art(for: .major(6), deck: .classic1909).face === major.face)
        XCTAssertFalse(provider.art(for: .major(6), deck: .astral).face === major.face)
        // The back must not be a face.
        XCTAssertFalse(provider.backArt().isMajor)
    }

    /// The one place the two kits' vocabularies meet: every method's kernel layout must
    /// agree with its position count, and the mapping must fall back safely.
    func testEveryMethodLayoutMatchesItsPositions() {
        for method in TarotKit.Spread.all {
            let layout = AppModel.layout(forMethodID: method.id)
            XCTAssertEqual(layout.slotCount, method.positions.count, method.id)
        }
        XCTAssertEqual(AppModel.layout(forMethodID: "stale-id").slotCount, 3)
        // Reduce Motion composes with every method, not just the default.
        for method in TarotKit.Spread.all {
            let reduced = AppModel.config(methodID: method.id, reduceMotion: true)
            XCTAssertTrue(reduced.reduceMotion, method.id)
            XCTAssertEqual(reduced.slotCount, method.positions.count, method.id)
        }
    }

    /// A skin is data: every registered skin must give all four suits and the majors a
    /// usable accent (a fully transparent accent means an invisible card).
    @MainActor
    func testEverySkinSpecIsComplete() {
        for skin in Skins.all {
            XCTAssertFalse(skin.id.isEmpty)
            XCTAssertFalse(skin.displayName.isEmpty)
            XCTAssertGreaterThan(skin.spec.majorAccent.a, 0)
            for suit in Suit.allCases {
                XCTAssertGreaterThan(skin.spec.accent(for: suit).a, 0, "\(skin.id)/\(suit)")
            }
            XCTAssertGreaterThan(skin.spec.faceLatticeAlpha, 0)
            XCTAssertFalse(skin.spec.backEmblem.isEmpty)
        }
    }
}
