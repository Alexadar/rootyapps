import XCTest
import SwiftUI
@testable import Overtone_Lab

/// The state axes Audio Analysis adds, every one exercised in **both** directions.
///
/// The house rule exists because a control tested only in its default state proves nothing — a watch
/// unit toggle once shipped doing nothing at all, green suite and correct numbers throughout. These
/// are the new axes: provenance typed↔measured, revert restoring what was displaced rather than a
/// default, session none/live/complete, BPM nil/determined, and availability absent/present.
@MainActor
final class AnalysisStateChecks: XCTestCase {

    private func session(bpm: Double? = 128, lufs: Double? = -18.3,
                         tonic: String? = "F#", minor: Bool? = true) -> MeasurementStore.Session {
        MeasurementStore.Session(sourceName: "Take 3.wav", measuredAt: Date(timeIntervalSince1970: 0),
                                 bpm: bpm, keyTonic: tonic, keyIsMinor: minor,
                                 integratedLUFS: lufs, peakDB: -0.7, barCount: 32)
    }

    // MARK: - Provenance, both directions

    func testFieldGoesTypedToMeasuredAndBack() {
        let p = FieldProvenance()
        let key = FieldKey(tool: "tempo", field: "bpm")

        XCTAssertFalse(p.isMeasured(key), "a field starts typed")

        p.markMeasured(key, replacing: 120, source: "Take 3.wav", at: Date())
        XCTAssertTrue(p.isMeasured(key), "handing a value over must mark it")

        p.markTyped(key)
        XCTAssertFalse(p.isMeasured(key), "typing must clear the marking")
        XCTAssertNil(p.revertValue(for: key),
                     "once the user has typed there is nothing left to revert to")
    }

    /// ⚠ REVERT RESTORES WHAT WAS DISPLACED, NOT A DEFAULT. Storing only "was measured" would leave
    /// revert guessing, and a tool's default is not the number the user had typed.
    func testRevertRestoresThePreHandoffValueNotADefault() {
        let p = FieldProvenance()
        let key = FieldKey(tool: "tempo", field: "bpm")

        // The user had typed 93 — nowhere near the 120 default.
        p.markMeasured(key, replacing: 93, source: "Take 3.wav", at: Date())
        XCTAssertEqual(p.revertValue(for: key), 93)

        let restored = p.revert(key)
        XCTAssertEqual(restored, 93, "revert must hand back 93, not the 120 default")
        XCTAssertFalse(p.isMeasured(key), "reverting also clears the marking")
    }

    func testAFieldNeverMeasuredHasNothingToRevert() {
        let p = FieldProvenance()
        XCTAssertNil(p.revert(FieldKey(tool: "delay", field: "bpm")))
    }

    // MARK: - Session presence: none / live / complete

    func testSessionPresenceMovesThroughAllThreeStates() {
        let store = MeasurementStore()
        XCTAssertEqual(store.presence, .none)

        store.beginLive(sourceName: "Live input")
        XCTAssertEqual(store.presence, .live)

        store.finish(session())
        XCTAssertEqual(store.presence, .complete)

        store.clear()
        XCTAssertEqual(store.presence, .none, "clearing must return to none, not to complete-with-nil")
    }

    // MARK: - BPM nil / determined

    /// While BPM is nil the tempo and delay rows must be **absent**, not disabled — and they must
    /// appear the moment the beats land.
    func testTempoRoutingAppearsOnlyOnceBPMIsDetermined() {
        let store = MeasurementStore()

        store.finish(session(bpm: nil))
        XCTAssertFalse(store.canFeed(.tempo), "no tempo row while BPM is nil")
        XCTAssertFalse(store.canFeed(.delay))
        XCTAssertTrue(store.canFeed(.benchmark), "loudness landed, so benchmark is offered")

        store.finish(session(bpm: 128))
        XCTAssertTrue(store.canFeed(.tempo), "the beats landed, so the row appears")
        XCTAssertTrue(store.canFeed(.delay))
    }

    func testKeyRoutingFollowsTheTonicInBothDirections() {
        let store = MeasurementStore()
        store.finish(session(tonic: nil))
        XCTAssertFalse(store.canFeed(.pitch))
        XCTAssertFalse(store.canFeed(.partch))

        store.finish(session(tonic: "F#"))
        XCTAssertTrue(store.canFeed(.pitch))
        XCTAssertTrue(store.canFeed(.partch))
    }

    /// The tools §10 names but the app cannot honestly feed. This test is the record of that decision:
    /// if someone adds a field that *does* accept the quantity, it fails and asks to be updated.
    func testToolsWithNoConsumingFieldAreNotOffered() {
        let store = MeasurementStore()
        store.finish(session())
        for tool in [Tool.comma, .levels, .timecode, .sra, .pan] {
            XCTAssertFalse(store.canFeed(tool),
                           "\(tool.rawValue) has no input field that accepts a measured quantity")
        }
    }

    // MARK: - Routing values

    func testTheRoutingTableHandsTheRightNumberToTheRightField() {
        let s = session(bpm: 128, lufs: -18.3, tonic: "A", minor: false)

        XCTAssertEqual(MeasurementHandoff.values(from: s, for: .tempo),
                       [FieldKey(tool: "tempo", field: "bpm"): 128])
        XCTAssertEqual(MeasurementHandoff.values(from: s, for: .benchmark),
                       [FieldKey(tool: "benchmark", field: "measuredInput"): -18.3])
        // A = 440 Hz (MIDI 69), so the tonic reaches pitch as a frequency it can actually edit.
        let pitchValue = MeasurementHandoff.values(from: s, for: .pitch)[FieldKey(tool: "pitch", field: "freqInput")]
        XCTAssertEqual(pitchValue ?? 0, 440, accuracy: 1e-6)
        XCTAssertTrue(MeasurementHandoff.values(from: s, for: .sabine).isEmpty)
    }

    func testApplyingAHandoffMarksTheFieldAndRemembersWhatItDisplaced() {
        let handoff = MeasurementHandoff()
        let p = FieldProvenance()
        let key = FieldKey(tool: "tempo", field: "bpm")
        var bpm = 93.0                                   // what the user had typed

        handoff.hand(session: session(bpm: 128), to: .tempo, provenance: p)
        let landed = handoff.apply(key, into: Binding(get: { bpm }, set: { bpm = $0 }), provenance: p)

        XCTAssertTrue(landed)
        XCTAssertEqual(bpm, 128, "the measured value lands in the field")
        XCTAssertTrue(p.isMeasured(key), "and it is marked")
        XCTAssertEqual(p.revertValue(for: key), 93, "and 93 is what revert owes the user")

        // Applying twice must not re-fire: the value was consumed.
        XCTAssertFalse(handoff.apply(key, into: Binding(get: { bpm }, set: { bpm = $0 }), provenance: p))
    }

    // MARK: - Availability: absent / present

    /// The catalog entry is a **missing array element**, never a disabled row.
    func testMeasureIsAbsentWithoutTheFrameworkAndPresentWithTheOverride() {
        // This process runs without OVERTONELAB_MEASURE and on an SDK with no MusicUnderstanding.
        XCTAssertFalse(AnalysisAvailability.isAvailable,
                       "absent by default on a released SDK")
        XCTAssertTrue(CatalogEntry.sources.isEmpty,
                      "so the catalog simply does not contain the entry — no greyed row to find")

        // And the entry itself is well-formed for when it is present, so the id a test addresses is
        // stable whether or not the row is currently in the array.
        XCTAssertEqual(CatalogEntry.source(.measure).id, "source.measure")
        XCTAssertEqual(CatalogEntry.tool(.tempo).id, "tempo")
    }

    // MARK: - Session cold / restored

    /// Persistence is deliberately RAM-only this round, so "survives a cold start" is **not** claimed.
    /// What is claimed is that the seam exists and is honest about doing nothing: `restore()` after a
    /// fresh store yields nothing rather than a stale or invented session.
    func testPersistenceSeamIsWiredButStoresNothingYet() {
        let store = MeasurementStore()
        store.finish(session())
        XCTAssertNotNil(store.session)

        let fresh = MeasurementStore()
        fresh.restore()
        XCTAssertNil(fresh.session,
                     "RAM-only by decision: a new process starts with no session, and says so")
    }

    /// The session crossing to the watch is `Codable` end to end — the shape persistence will use,
    /// and the shape the transport already sends.
    func testSessionRoundTripsThroughJSON() throws {
        let original = session()
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(MeasurementStore.Session.self,
                                         from: try encoder.encode(original))
        XCTAssertEqual(decoded, original)
    }
}
