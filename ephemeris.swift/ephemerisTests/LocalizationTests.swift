import Testing
import Foundation
import SwiftUI
@testable import Ephemeris

/// Localization is easy to *appear* to work — the catalog silently falls back to English, so a
/// half-wired setup looks fine in the simulator and ships untranslated. These tests assert the
/// two things that actually matter: every language is really in the bundle, and choosing a
/// language that isn't the system language really changes the text.
@Suite("Localization")
@MainActor
struct LocalizationTests {

    /// The languages we claim to ship.
    static let shipped = ["uk", "de", "fr", "es", "it", "pl", "cs", "hu", "ro",
                          "el", "tr", "nl", "sv", "ja", "ko", "pt-BR"]

    @Test func everyShippedLanguageIsInTheBundle() {
        let available = Set(Bundle.main.localizations)
        for code in Self.shipped {
            #expect(available.contains(code), "\(code) missing from the built bundle")
        }
    }

    /// Every language must resolve every representative key to something non-empty, and each key
    /// must genuinely vary across languages.
    ///
    /// Note the assertion is *not* "differs from the English key" — several translations are
    /// legitimately identical ("Aries" is "Aries" in Spanish, "Mars" is "Mars" in German), and
    /// asserting difference would fail on correct data. Requiring several distinct values across
    /// the set still catches the real failure mode: a catalog that isn't wired up and silently
    /// falls back to English everywhere.
    @Test func keyStringsResolveInEveryLanguage() throws {
        let keys = ["Positions", "Aspects", "Houses", "Settings", "Language", "Aries", "Sun",
                    "%@ enters %@", "New Moon in %@", "%@ stations retrograde", "ingress"]
        for key in keys {
            var resolved: Set<String> = []
            for code in Self.shipped {
                let path = try #require(Bundle.main.path(forResource: code, ofType: "lproj"))
                let bundle = try #require(Bundle(path: path))
                let value = bundle.localizedString(forKey: key, value: nil, table: nil)
                let note = "\(code): '\(key)' resolved to empty"
                #expect(!value.isEmpty, "\(note)")
                resolved.insert(value)
            }
            let note = "'\(key)' produced only \(resolved.count) distinct values across 16 "
                     + "languages — the catalog is probably not wired up"
            #expect(resolved.count > 3, "\(note)")
        }
    }

    /// The whole point of the feature: an override that differs from the system language.
    /// Verified against known-correct translations so a silently-English build fails here.
    @Test func overrideProducesTheChosenLanguageNotTheSystemOne() throws {
        let expected: [(String, String, String)] = [
            ("uk", "Positions", "Позиції"),
            ("de", "Houses", "Häuser"),
            ("ja", "Settings", "設定"),
            ("uk", "Aries", "Овен"),
            ("de", "Sun", "Sonne"),
        ]
        for (code, key, want) in expected {
            let path = try #require(Bundle.main.path(forResource: code, ofType: "lproj"))
            let bundle = try #require(Bundle(path: path))
            #expect(bundle.localizedString(forKey: key, value: nil, table: nil) == want,
                    "\(code)/\(key)")
        }
    }

    // MARK: The store

    @Test func languageStoreDefaultsToSystemAndPersists() {
        let key = "appLanguage"
        UserDefaults.standard.removeObject(forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let first = LanguageStore()
        #expect(first.selected == .system)
        #expect(first.locale == .autoupdatingCurrent)   // follows the device

        first.selected = .uk
        #expect(first.locale.identifier == "uk")

        let second = LanguageStore()                     // relaunch
        #expect(second.selected == .uk, "language did not survive a restart")
    }

    /// Every case must map to a real locale and carry an endonym — a blank entry would render an
    /// unpickable row in Settings.
    @Test func everyLanguageCaseIsUsable() {
        for lang in AppLanguage.allCases {
            #expect(!lang.endonym.isEmpty, "\(lang.rawValue) has no endonym")
            if lang == .system {
                #expect(lang.locale == nil)
            } else {
                #expect(lang.locale != nil, "\(lang.rawValue) has no locale")
            }
        }
        // The picker must offer exactly what the bundle ships (+ system + en).
        let offered = Set(AppLanguage.allCases.map(\.rawValue)).subtracting(["", "en"])
        #expect(offered == Set(Self.shipped), "picker and bundle disagree: \(offered.symmetricDifference(Set(Self.shipped)))")
    }

    /// Card headers pass their key as a plain `String` (they have to — `NebulaCardHeader`
    /// uppercases it), which means the compiler's key extraction can't see them and a typo would
    /// ship silently as untranslated English. This is the replacement safety net.
    @Test func cardHeaderTitlesAreAllCatalogKeys() throws {
        let headers = ["Moment", "Positions", "Aspects", "Houses", "Events",
                       "Synodic cycle", "Current phase", "Upcoming events"]
        for key in headers {
            for code in Self.shipped {
                let path = try #require(Bundle.main.path(forResource: code, ofType: "lproj"))
                let bundle = try #require(Bundle(path: path))
                let value = bundle.localizedString(forKey: key, value: "MISSING", table: nil)
                #expect(value != "MISSING", "\(code): card header '\(key)' is not in the catalog")
            }
        }
    }

    /// `L.string` is what makes the uppercased headers honour the override. `String(localized:)`
    /// looks equivalent and isn't — its `locale:` argument formats interpolations but does not
    /// select the `.lproj`, so it silently returns the system language. Guard the difference.
    @Test func explicitLookupHonoursTheChosenLanguage() {
        #expect(L.string("Events", locale: Locale(identifier: "uk")) == "Події")
        #expect(L.string("Houses", locale: Locale(identifier: "de")) == "Häuser")
        #expect(L.string("Settings", locale: Locale(identifier: "ja")) == "設定")
        // pt-BR must survive Locale's underscore normalisation ("pt_BR" → "pt-BR.lproj").
        #expect(L.string("Events", locale: Locale(identifier: "pt-BR")) != "Events")
        // An unshipped language falls back to the key rather than crashing.
        #expect(L.string("Events", locale: Locale(identifier: "xx")) == "Events")
    }

    /// The Kit composes event and phase text combinatorially — `AstroEvent.label()` builds ~1,300
    /// sentences like "Mars enters Aries", and `SynodicPhase.title` is assembled at runtime. None
    /// of those can ever be a catalog key, so the UI rebuilds them from *pattern* keys instead.
    /// This asserts every pattern exists and keeps its placeholders: a translation that drops a
    /// `%@` compiles fine and then renders an event with the planet name missing.
    @Test func eventPatternsExistAndKeepTheirPlaceholders() throws {
        let patterns: [(String, Int)] = [
            ("%@ enters %@", 2), ("New Moon in %@", 1), ("Full Moon in %@", 1),
            ("%@ stations retrograde", 1), ("%@ stations direct", 1),
            ("%@ inferior conjunction", 1), ("%@ superior conjunction", 1),
            ("%@ greatest elongation east", 1), ("%@ greatest elongation west", 1),
            ("%@ conjunction Sun", 1), ("%@ opposition Sun", 1), ("%@ %@ %@", 3),
            ("%@ is undefined this far from the equator — showing Whole Sign.", 1),
            ("orb %@°", 1),
        ]
        for (key, count) in patterns {
            for code in Self.shipped {
                let path = try #require(Bundle.main.path(forResource: code, ofType: "lproj"))
                let bundle = try #require(Bundle(path: path))
                let value = bundle.localizedString(forKey: key, value: "MISSING", table: nil)
                #expect(value != "MISSING", "\(code): pattern '\(key)' has no translation")
                // Positional ("%1$@") and plain ("%@") specifiers both count as one placeholder.
                let found = value.components(separatedBy: "%").count - 1
                let note = "\(code): '\(key)' → '\(value)' has \(found) placeholders, expected \(count)"
                #expect(found == count, "\(note)")
            }
        }
    }

    /// `Day %lld of %lld` is the one integer-formatted pattern; a `%@` there crashes at render.
    @Test func integerPatternKeepsIntegerSpecifiers() throws {
        for code in Self.shipped {
            let path = try #require(Bundle.main.path(forResource: code, ofType: "lproj"))
            let bundle = try #require(Bundle(path: path))
            let value = bundle.localizedString(forKey: "Day %lld of %lld", value: "MISSING", table: nil)
            #expect(value != "MISSING", "\(code): missing")
            let note = "\(code): 'Day %lld of %lld' → '\(value)' lost an lld specifier"
            #expect(value.components(separatedBy: "lld").count - 1 == 2, "\(note)")
        }
    }

    /// `L.loc` is the boundary that lets EphemerisKit keep returning English (its strings double
    /// as dictionary keys, ids, the aspect-colour switch and the CSV export contract).
    @Test func kitEnglishIsUsableAsACatalogKey() throws {
        // The exact strings the Kit hands back must exist as catalog keys.
        for key in ["Aries", "Sun", "Conjunction", "Whole Sign"] {
            let path = try #require(Bundle.main.path(forResource: "de", ofType: "lproj"))
            let bundle = try #require(Bundle(path: path))
            #expect(bundle.localizedString(forKey: key, value: nil, table: nil) != key,
                    "Kit string '\(key)' has no catalog entry")
        }
    }
}
