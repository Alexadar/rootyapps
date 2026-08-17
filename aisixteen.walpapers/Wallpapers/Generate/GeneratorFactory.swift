import Foundation
import GenerationKit

/// Debug-only launch overrides, behind one door.
///
/// The house pattern (see Overtone Lab's `LaunchOverride`): environment variables select fixtures,
/// and the whole mechanism compiles out of Release. One door rather than scattered
/// `ProcessInfo` reads, so there is exactly one place to check that no test hook can be reached in
/// a shipped build.
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

/// Chooses the generator the app runs against.
///
/// Today both choices are mocks. When the real pipeline lands it is added here and nothing above
/// this line changes — that is the entire purpose of the `ImageGenerator` protocol, and this is the
/// one place that knows which implementation exists.
enum GeneratorFactory {

    /// `WALLPAPERS_GENERATOR` — `failing` for the error path, `fast` for a quick flow, otherwise the
    /// realistic 10–30 s mock.
    static let overrideKey = "WALLPAPERS_GENERATOR"

    static func make() -> any ImageGenerator {
        #if WALLPAPERS_MOCK
        // The Mock configuration ships without the model, so there is nothing to prefer. Realistic
        // timing on purpose: a preview-video take or a UI judgement made against an instant
        // generator is a judgement about a different app.
        return MockImageGenerator(speed: .device)
        #else
        // The real model wins whenever it is present. Today that means a folder in the app bundle;
        // once the Background Assets pack ships it becomes the installed pack's URL, and this is
        // the only line that changes.
        if !LaunchOverride.isSet(overrideKey),
           let resources = CoreMLImageGenerator.bundledResourcesURL() {
            return CoreMLImageGenerator(resourcesURL: resources)
        }

        switch LaunchOverride.value(overrideKey) {
        case "mock":
            return MockImageGenerator(speed: .device)
        case "failing":
            return FailingImageGenerator(failAtStep: 11, error: .outOfMemory, speed: .fast)
        case "failing-early":
            // Fails before the frame reveal, so the other half of the failure transition is
            // reachable too — capsule straight to card, without ever becoming a picture.
            return FailingImageGenerator(failAtStep: 2, error: .failed(reason: "The model stopped part-way through."), speed: .fast)
        case "fast":
            return MockImageGenerator(speed: .fast)
        case "instant":
            return MockImageGenerator(speed: .instant)
        default:
            return MockImageGenerator(speed: .device)
        }
        #endif
    }
}
