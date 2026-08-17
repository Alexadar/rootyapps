import Foundation
import CoreGraphics
import EnhanceKit
import RecipeKit
import DiffusionRuntime

/// Debug-only launch overrides, behind one door.
///
/// The house pattern: environment variables select fixtures, and the whole mechanism compiles out of
/// Release. One door rather than scattered `ProcessInfo` reads, so there is exactly one place to
/// check that no test hook can be reached in a shipped build.
enum LaunchOverride {
    static func value(_ key: String) -> String? {
        #if DEBUG
        ProcessInfo.processInfo.environment[key]
        #else
        nil
        #endif
    }

    static func isSet(_ key: String) -> Bool { value(key) != nil }
    static func flag(_ key: String) -> Bool { value(key) == "1" }
}

/// Chooses the enhancer a pass runs against.
///
/// **This is the one place that knows which implementations exist.** The real pipeline wins whenever
/// its pack is on the machine; otherwise the app runs the mock and behaves identically everywhere
/// above `PhotoEnhancer`.
enum EnhancerFactory {

    /// `STUDIO_ENHANCER` — `mock` / `fast` / `instant` / `failing` / `failing-early` force a mock
    /// even when the real pack is present.
    static let overrideKey = "STUDIO_ENHANCER"

    /// `STUDIO_MODEL_PATH` — an absolute path to the pack's `Resources` folder.
    ///
    /// ⚠️ This is how a development build runs the real model **without copying 1.2 GB into the app**.
    /// The pack lives once, in `aisixteen.models/`, and a Mac run points at it. Device builds will
    /// get it from a Background Assets pack instead; that is the only line that changes.
    static let modelPathKey = "STUDIO_MODEL_PATH"

    /// The enhancer for one pass.
    ///
    /// Takes the strength and the photo because the real pass needs both **before it starts**: the
    /// denoise fraction fixes how many steps the scheduler runs, and the photo's shape fixes how
    /// many tiles there are. Together they are the step total the progress capsule shows from its
    /// first frame.
    static func make(strength: Strength, photo: CGImage) -> any PhotoEnhancer {
        if let forced = mock(named: LaunchOverride.value(overrideKey)) { return forced }

        if let resources = resourcesURL(),
           let real = StudioEnhancer(resources: resources,
                                     strength: strength,
                                     photoWidth: photo.width,
                                     photoHeight: photo.height) {
            return real
        }

        // Realistic timing on purpose: a UI judgement made against an instant enhancer is a
        // judgement about a different app.
        return MockPhotoEnhancer(speed: .device)
    }

    private static func mock(named name: String?) -> (any PhotoEnhancer)? {
        switch name {
        case "instant":       return MockPhotoEnhancer(speed: .instant)
        case "fast":          return MockPhotoEnhancer(speed: .fast)
        case "mock":          return MockPhotoEnhancer(speed: .device)
        case "failing":       return FailingPhotoEnhancer(failAtStep: 11, error: .outOfMemory,
                                                          speed: .fast)
        case "failing-early": return FailingPhotoEnhancer(
                                        failAtStep: 2,
                                        error: .failed(reason: "The model stopped part-way through."),
                                        speed: .fast)
        default:              return nil
        }
    }

    /// Where the model is, if it is anywhere.
    ///
    /// Bundle first so a shipped app never depends on an environment variable; the override exists
    /// for development on a Mac, where copying the pack per build would be minutes of I/O for
    /// nothing.
    static func resourcesURL() -> URL? {
        if let bundled = Bundle.main.url(forResource: "sd15cn", withExtension: nil),
           FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }
        if let path = LaunchOverride.value(modelPathKey) {
            let url = URL(fileURLWithPath: path)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        return nil
    }

    /// True when no real model is reachable, so the app is producing procedural output.
    ///
    /// ⚠️ Nothing produced in this state may be screenshotted for the store — it is an unsharp mask,
    /// not model output.
    static var isRunningMock: Bool {
        LaunchOverride.isSet(overrideKey) || resourcesURL() == nil
    }
}
