import Foundation
// `os(iOS)`, NOT `canImport(ActivityKit)`. The module imports cleanly on macOS and then every type
// inside it is marked unavailable, so canImport compiles and the first use does not.
#if os(iOS)
import ActivityKit
#endif

/// The Live Activity's contract, compiled into BOTH the app and the widget extension.
///
/// Shared as a source file rather than duplicated: a `ContentState` that has drifted between the
/// two processes is a Live Activity that silently stops updating, with no error anywhere.
///
/// ⚠️ iOS only. The design handoff is explicit that macOS gets a standard user notification
/// instead, so this whole type is behind `canImport(ActivityKit)`.
enum RedesignActivity {
    /// The App Group the forming thumbnail travels through.
    ///
    /// ActivityKit's content state is capped at a few KB and cannot carry a picture, so the
    /// downscaled latent is written to the shared container as a file and the widget reads it back
    /// by name.
    static let appGroupID = "group.oleksandr.aisixteen.architecture"
    static let thumbnailFolder = "Activity"

    /// The activity's accent, as hex.
    ///
    /// Lives HERE rather than in `ARC` because this file is the only source compiled into both the
    /// app and the widget — `Architecture/Design/Tokens.swift` is not in the extension's sources,
    /// so the widget cannot see `ARC` at all. It was previously the literal `0xE08A5C` written out
    /// four times in the widget and declared a fifth time in `ARC.accentOnDark`, where nothing
    /// referenced it. A lighter terracotta than `ARC.accent`, for legibility on the dark lock
    /// screen rather than on canvas.
    static let accentHex: UInt32 = 0xE08A5C

    static func thumbnailURL(jobID: String) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(thumbnailFolder, isDirectory: true)
            .appendingPathComponent("\(jobID).jpg")
    }
}

#if os(iOS)
struct RedesignActivityAttributes: ActivityAttributes {

    struct ContentState: Codable, Hashable {
        var spaceName: String
        var styleName: String
        /// `GenerationStage.rawValue`, deliberately a String so the widget target does not have to
        /// link RedesignKit for one enum.
        var stage: String
        var step: Int
        var totalSteps: Int
        var queuedCount: Int
        /// Suspended. `step` and `totalSteps` are FROZEN while this is true.
        ///
        /// The handoff's rule, and the reason this field exists at all: the activity reads
        /// "Waiting for you" and NEVER shows progress it is not making. An activity that keeps
        /// ticking while the app is asleep is lying on the lock screen, where the user cannot even
        /// open the app to check.
        var waiting: Bool
        /// A FILE NAME in the App Group container, never the bytes.
        var thumbnailName: String?
        /// The step the thumbnail was written at. Without it the widget serves a cached image for
        /// an unchanged file name and the picture never appears to form.
        var thumbnailStamp: Int
        var remainingText: String?

        init(spaceName: String,
             styleName: String,
             stage: String,
             step: Int,
             totalSteps: Int,
             queuedCount: Int,
             waiting: Bool,
             thumbnailName: String?,
             thumbnailStamp: Int,
             remainingText: String?) {
            self.spaceName = spaceName
            self.styleName = styleName
            self.stage = stage
            self.step = step
            self.totalSteps = totalSteps
            self.queuedCount = queuedCount
            self.waiting = waiting
            self.thumbnailName = thumbnailName
            self.thumbnailStamp = thumbnailStamp
            self.remainingText = remainingText
        }

        /// The line under the title. Never a percentage, never a fabricated number.
        var statusLine: String {
            if waiting { return "Waiting for you — opens where it left off" }
            var line = "\(stage) · step \(step) of \(totalSteps)"
            if let remainingText { line += " · \(remainingText)" }
            return line
        }

        var fraction: Double {
            guard totalSteps > 0 else { return 0 }
            return min(max(Double(step) / Double(totalSteps), 0), 1)
        }
    }

    /// Static for the life of the activity.
    var projectID: String
    var jobID: String
    /// "Variation 2 of 3".
    var variationLabel: String
}
#endif
