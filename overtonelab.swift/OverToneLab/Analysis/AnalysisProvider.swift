import Foundation

/// The seam between "something listened to audio" and everything else.
///
/// Analysis is built against this protocol, never against `MusicUnderstanding` directly, for a reason
/// that is not architectural taste: the framework is **absent from the released SDK**, so code written
/// against it cannot be compiled, type-checked or run here. Everything above this line — the store,
/// provenance, routing, the screens — is exercised through `FixtureAnalysisProvider` and is real,
/// tested code. Only the adapter below the line is unverifiable, and it is a marked stub.
@MainActor
protocol AnalysisProvider {
    /// A human name for what is being measured: a file name, or "Live input".
    var sourceName: String { get }

    /// Begin producing values. `onUpdate` may be called many times as results arrive — BPM commonly
    /// lands after loudness, because it needs two beats.
    func start(onUpdate: @escaping (MeasurementStore.Session) -> Void) async throws

    func stop()
}

enum AnalysisProviderError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Audio analysis is not available in this build."
        }
    }
}

/// Chooses the provider for this build.
///
/// On the released SDK there is no framework, so the fixture is the only provider — which is exactly
/// what makes the feature demonstrable and testable before the OS ships.
@MainActor
enum AnalysisProviderFactory {
    static func make() -> AnalysisProvider? {
        if let fixture = FixtureAnalysisProvider.fromLaunchOverride() { return fixture }
        #if canImport(MusicUnderstanding)
        if #available(iOS 27, macOS 27, *) { return MusicUnderstandingProvider() }
        #endif
        return nil
    }
}
