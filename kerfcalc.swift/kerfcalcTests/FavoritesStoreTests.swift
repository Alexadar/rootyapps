import Testing
import Foundation
@testable import KerfCalc

/// Unit tests for the favourites persistence logic (offline UserDefaults-backed store).
@MainActor
@Suite struct FavoritesStoreTests {

    private func freshDefaults() -> UserDefaults {
        let suite = "kerf.test.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    @Test func defaultSeed() {
        let s = FavoritesStore(defaults: freshDefaults())
        #expect(s.favoriteTools == [.rafter, .concrete, .stairs])
        #expect(s.isFavorite(.rafter))
        #expect(!s.isFavorite(.area))
    }

    @Test func toggleAddsThenRemoves() {
        let s = FavoritesStore(defaults: freshDefaults())
        s.toggle(.area)
        #expect(s.isFavorite(.area))
        #expect(s.favoriteTools.last == .area)      // appended in starred order
        s.toggle(.area)
        #expect(!s.isFavorite(.area))
    }

    @Test func toggleExistingRemovesIt() {
        let s = FavoritesStore(defaults: freshDefaults())
        s.toggle(.rafter)                            // seeded → toggling removes
        #expect(!s.isFavorite(.rafter))
        #expect(!s.favoriteTools.contains(.rafter))
    }

    @Test func persistsAcrossInstances() {
        let d = freshDefaults()
        let s1 = FavoritesStore(defaults: d)
        s1.toggle(.miter)                            // add
        s1.toggle(.rafter)                           // remove a seed
        let s2 = FavoritesStore(defaults: d)         // reload from the same store
        #expect(s2.isFavorite(.miter))
        #expect(!s2.isFavorite(.rafter))
    }

    @Test func parseDropsGarbageAndEmpties() {
        #expect(FavoritesStore.parse("") == [])
        #expect(FavoritesStore.parse("rafter,,stairs") == ["rafter", "stairs"])
        let d = freshDefaults()
        d.set("rafter,bogusid,stairs", forKey: FavoritesStore.key)
        let s = FavoritesStore(defaults: d)
        #expect(s.favoriteTools == [.rafter, .stairs])   // unknown id dropped, order kept
    }
}
