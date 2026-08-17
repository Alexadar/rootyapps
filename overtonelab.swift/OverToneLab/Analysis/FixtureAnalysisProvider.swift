import Foundation

/// Replays a session from `OVERTONELAB_SESSION` — **no microphone, no framework, no permission**.
///
/// This is what lets the whole feature be tested before the OS that powers it exists: provenance
/// marking, revert, routing to ten tools, the BPM-nil state and the watch handoff are all driven from
/// a JSON fixture a UI test supplies. It is compiled out of Release builds with the rest of
/// `LaunchOverride`, so it cannot be reached by a customer.
///
/// The two-phase replay is not decoration. BPM genuinely arrives late — it needs two beats — so the
/// fixture emits loudness first and BPM second, which is the ordering the UI has to survive: hero
/// reading `—— listening`, Send buttons absent rather than disabled, then both appearing at once.
@MainActor
final class FixtureAnalysisProvider: AnalysisProvider {
    private let session: MeasurementStore.Session
    private var cancelled = false

    var sourceName: String { session.sourceName }

    init(session: MeasurementStore.Session) { self.session = session }

    /// `OVERTONELAB_SESSION=<json>` → a provider, or nil when the variable is absent or unparseable.
    static func fromLaunchOverride() -> FixtureAnalysisProvider? {
        guard let raw = LaunchOverride.value("OVERTONELAB_SESSION"),
              let data = raw.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let session = try? decoder.decode(MeasurementStore.Session.self, from: data) else {
            // A malformed fixture must not silently look like "no measurement" — that would make a
            // broken test read as a passing one.
            assertionFailure("OVERTONELAB_SESSION is not a decodable Session")
            return nil
        }
        return FixtureAnalysisProvider(session: session)
    }

    func start(onUpdate: @escaping (MeasurementStore.Session) -> Void) async throws {
        cancelled = false

        // Phase 1 — everything except tempo. This is the state where BPM is nil and the screen has to
        // say so honestly.
        var partial = session
        partial.bpm = nil
        partial.barCount = nil
        onUpdate(partial)

        try? await Task.sleep(for: .milliseconds(400))
        guard !cancelled else { return }

        // Phase 2 — the beats have landed.
        onUpdate(session)
    }

    func stop() { cancelled = true }
}
