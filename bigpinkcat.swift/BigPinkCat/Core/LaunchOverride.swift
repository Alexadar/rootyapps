import Foundation

/// The deep link the UI tests and the capture pipelines use to jump straight to a demo.
///
/// `BIGPINKCAT_DEMO=<rawValue>` selects a demo at launch, which is how an XCUITest reaches scene 14
/// without scroll-hunting a list and how the reel recorder gets a deterministic starting frame.
///
/// **Gated to DEBUG.** In Release the environment is never consulted, so the shipping build carries
/// no env back door — the same arrangement as `kerfcalc/LaunchOverride.swift`.
enum LaunchOverride {
    static var demo: Demo? {
        #if DEBUG
        guard let raw = ProcessInfo.processInfo.environment["BIGPINKCAT_DEMO"],
              let value = Int(raw), let demo = Demo(rawValue: value) else { return nil }
        return demo
        #else
        return nil
        #endif
    }

    /// Freeze the clock, so a captured frame is reproducible rather than "whenever the shot landed".
    static var frozenTime: Double? {
        #if DEBUG
        guard let raw = ProcessInfo.processInfo.environment["BIGPINKCAT_TIME"] else { return nil }
        return Double(raw)
        #else
        return nil
        #endif
    }
}
