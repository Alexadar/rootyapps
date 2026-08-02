import Testing
import Foundation
import EphemerisKit

@Suite("Event catalog (numeric codes)")
struct EventCatalogTests {

    @Test func codesAreUniqueAndContiguous() {
        let codes = EventCatalog.entries.map { $0.code }
        #expect(Set(codes) == Set(0..<EventCatalog.entries.count))
        #expect(EventCatalog.labelsByCode.count == EventCatalog.entries.count)
        #expect(EventCatalog.codeByKey.count == EventCatalog.entries.count)
    }

    @Test func perClassCounts() {
        func count(_ prefix: String) -> Int { EventCatalog.entries.filter { $0.key.hasPrefix(prefix) }.count }
        #expect(count("ingress.") == 120)   // 10 bodies × 12 signs
        #expect(count("lunation.") == 24)    // 2 phases × 12 signs
        #expect(count("station.") == 16)     // 8 planets × 2
        #expect(count("sun.") == 20)         // inferior(2×4) + superior(6×2)
        #expect(count("aspect.") == 140)     // C(8,2)=28 pairs × 5 aspects
        #expect(EventCatalog.entries.count == 320)
    }

    @Test func everyGeneratedEventResolvesToACode() {
        let year = DateInterval(start: utc(2026, 1, 1), end: utc(2026, 12, 31, 23, 59))
        let evs = EventTimeline.allEvents(in: year)
        #expect(!evs.isEmpty)
        for e in evs {
            #expect(e.code >= 0)
            #expect(EventCatalog.labelsByCode[e.code] != nil)
            #expect(e.label() == EventCatalog.labelsByCode[e.code])
        }
    }

    @Test func keyToCodeRoundTrips() {
        for entry in EventCatalog.entries {
            #expect(EventCatalog.codeByKey[entry.key] == entry.code)
            #expect(EventCatalog.labelsByCode[entry.code] == entry.label)
        }
    }
}
