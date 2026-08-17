import Foundation
import MeasureKit

/// One measurement session, and the routing question "does this tool consume anything?".
///
/// Held by `RootView` as a `@StateObject`, a sibling of `FavoritesStore`, so results live **outside**
/// the navigation stack: popping Analysis discards a view and not a session. Measure once, visit three
/// calculators, come back — still there.
@MainActor
final class MeasurementStore: ObservableObject {

    /// `Codable` end to end. Nothing writes it to disk this round (see `SessionPersistence`), but the
    /// shape is the one persistence will use, and it is also what crosses to the watch.
    struct Session: Codable, Equatable, Sendable {
        var id: UUID
        var sourceName: String        // "Take 3.wav", "Live input"
        var measuredAt: Date
        /// nil until two beats land — never 0. See `Measure.bpm`.
        var bpm: Double?
        var keyTonic: String?
        var keyIsMinor: Bool?
        var integratedLUFS: Double?
        var peakDB: Double?
        var barCount: Int?

        init(id: UUID = UUID(), sourceName: String, measuredAt: Date,
                    bpm: Double? = nil, keyTonic: String? = nil, keyIsMinor: Bool? = nil,
                    integratedLUFS: Double? = nil, peakDB: Double? = nil, barCount: Int? = nil) {
            self.id = id; self.sourceName = sourceName; self.measuredAt = measuredAt
            self.bpm = bpm; self.keyTonic = keyTonic; self.keyIsMinor = keyIsMinor
            self.integratedLUFS = integratedLUFS; self.peakDB = peakDB; self.barCount = barCount
        }

        var keyName: String? { Measure.keyName(tonic: keyTonic, isMinor: keyIsMinor) }
    }

    /// Presence, as three states rather than an optional with a flag bolted on: nothing measured yet,
    /// a capture in progress whose numbers are still arriving, and a finished session.
    enum Presence: Equatable { case none, live, complete }

    @Published private(set) var session: Session?
    @Published private(set) var isLive = false

    var presence: Presence {
        if isLive { return .live }
        return session == nil ? .none : .complete
    }

    private let persistence: SessionPersistence

    init(persistence: SessionPersistence = InMemorySessionPersistence()) {
        self.persistence = persistence
    }

    // MARK: - Lifecycle

    func beginLive(sourceName: String) {
        isLive = true
        session = Session(sourceName: sourceName, measuredAt: Date())
    }

    /// Update the in-flight session. BPM arriving late is the normal case, not an edge one.
    func update(_ mutate: (inout Session) -> Void) {
        guard var s = session else { return }
        mutate(&s)
        session = s
    }

    func finish(_ s: Session) { isLive = false; session = s; persist() }
    func store(_ s: Session) { isLive = false; session = s; persist() }

    func clear() {
        isLive = false
        session = nil
        persistence.clear()
    }

    func persist() { if let session { persistence.save(session) } }
    func restore() { session = persistence.load() }

    // MARK: - Routing

    /// Does this tool consume anything in the current session?
    ///
    /// The rule is that a handed value must land in an existing input field. Where §10's routing
    /// table names a tool with no field that accepts the quantity, the row is **not offered** — a
    /// Send button that puts a number somewhere it does not belong would be a wrong answer wearing a
    /// measured badge, which is worse than no button.
    ///
    /// Fed:      BPM → tempo, delay.  Key → pitch (tonic frequency), partch (lower pitch).
    ///           Integrated LUFS → benchmark ("your measured loudness").
    ///
    /// NOT fed, each for a specific missing input rather than by omission:
    ///   • `comma`    — takes an EDO count, a frequency ratio and a cents value; a tonic is none.
    ///   • `levels`   — its inputs are volts, two comparison levels and a bit depth. There is no
    ///                  dBFS field for a true peak to land in.
    ///   • `timecode` — takes a frame count, not bars. Converting would require inventing a meter
    ///                  and a frame rate, and an invented number must not carry provenance.
    ///   • `sra`, `pan` — consume instrument activity, which `Session` does not carry.
    /// Also parked by §10 itself: pace (nothing consumes it) and structure → room tools (the physics
    /// does not support the link).
    func canFeed(_ tool: Tool) -> Bool {
        guard let s = session else { return false }
        switch tool {
        case .tempo, .delay:            return s.bpm != nil
        case .pitch, .partch:           return s.keyTonic != nil
        case .benchmark:                return s.integratedLUFS != nil
        default:                        return false
        }
    }

    /// Every tool this session can feed, in catalog order.
    var feedableTools: [Tool] { Tool.allCases.filter(canFeed) }
}

// MARK: - Persistence seam (unwired on purpose)

/// The seam persistence will arrive through. Deliberately not file-backed this round: the session is
/// RAM-only by decision, so a background kill loses it. `Session` is already `Codable`, so switching
/// this over is one implementation, not a redesign.
protocol SessionPersistence: Sendable {
    func save(_ session: MeasurementStore.Session)
    func load() -> MeasurementStore.Session?
    func clear()
}

struct InMemorySessionPersistence: SessionPersistence {
    init() {}
    func save(_ session: MeasurementStore.Session) {}
    func load() -> MeasurementStore.Session? { nil }
    func clear() {}
}
