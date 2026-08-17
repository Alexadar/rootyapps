import Foundation
import RedesignKit

/// The live coach line: one sentence, state-driven, no tutorial and no modal onboarding.
///
/// The handoff is specific that this is ONE line that changes, not a lesson: "tilt → hold level;
/// too close → step back". The three axes are level, distance and light, and a green dot means the
/// shot is usable.
///
/// Pure, so every branch is reachable in a unit test. `CaptureView` shipped `coach` and
/// `shotUsable` as `@State` constants that were never mutated — which meant the amber state had
/// never been seen by anything, including a person.
struct CoachLine: Equatable {

    enum Fault: Equatable {
        case tilted
        case tooClose
        case tooFar
        case tooDark
        case none
    }

    let mode: DirectionMode
    let fault: Fault

    /// True when the shot is worth taking. The dot is green here and amber otherwise.
    var isUsable: Bool { fault == .none }

    var text: String {
        switch fault {
        case .tilted: return "Hold level"
        case .tooClose: return "Step back"
        case .tooFar: return mode == .interior ? "Step closer" : "A little closer"
        case .tooDark: return "Needs more light"
        case .none: return Self.idleText(mode)
        }
    }

    /// The default line. Exterior differs because the framing advice genuinely differs — you back
    /// away from a facade and you cannot back away from a wall.
    static func idleText(_ mode: DirectionMode) -> String {
        switch mode {
        case .interior: return "Level · whole wall in frame · good light"
        case .exterior: return "Stand across the street · whole facade in frame"
        }
    }

    /// Evaluate the three axes.
    ///
    /// One fault at a time, in priority order: a sentence that says three things at once is a
    /// sentence nobody reads while holding a phone up at a wall.
    ///
    /// - Parameters:
    ///   - roll: device roll in degrees from level.
    ///   - pitch: device pitch in degrees from vertical.
    ///   - nearestDisparity: the 95th percentile of the depth frame, or nil when there is no depth.
    ///   - relativeLight: 0…1, from the camera's exposure.
    static func evaluate(mode: DirectionMode,
                         roll: Double,
                         pitch: Double,
                         nearestDisparity: Float?,
                         relativeLight: Double) -> CoachLine {
        // Level first: it is the one the user can fix instantly and the one that most affects
        // whether the geometry claim survives.
        if abs(roll) > tiltTolerance || abs(pitch) > tiltTolerance {
            return CoachLine(mode: mode, fault: .tilted)
        }
        if relativeLight < darkThreshold {
            return CoachLine(mode: mode, fault: .tooDark)
        }
        if let nearest = nearestDisparity {
            if nearest > tooCloseDisparity { return CoachLine(mode: mode, fault: .tooClose) }
            if nearest < tooFarDisparity { return CoachLine(mode: mode, fault: .tooFar) }
        }
        return CoachLine(mode: mode, fault: .none)
    }

    /// Generous, because a phone held by a person is never perfectly level and a coach line that
    /// is amber the whole time is a coach line nobody looks at.
    static let tiltTolerance: Double = 8
    static let darkThreshold: Double = 0.18
    /// Disparity is large when near. Above this the camera is close enough that the frame is one
    /// surface, and a redesign of one surface is not a redesign of a space.
    static let tooCloseDisparity: Float = 0.9
    static let tooFarDisparity: Float = 0.05
}
