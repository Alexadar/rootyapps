import Foundation

/// How much time one Digital Crown detent moves.
///
/// A single fixed step cannot serve this app. The Moon moves ~13°/day so hours are the right
/// grain for watching it; the outer planets move ~0.01°/day so weeks or months are needed before
/// anything visibly happens. Locking the Crown to days made both cases feel wrong at once.
///
/// Tapping the header cycles through these, which keeps it a one-handed gesture — there is no
/// room on a 41mm screen for a picker, and reaching for one defeats the point of the Crown.
enum ScrubStep: Int, CaseIterable {
    case hour, day, week, month

    /// Days per detent. The Crown reports a continuous value, so these are deliberately small
    /// enough that motion reads as a sweep rather than a jump.
    var daysPerDetent: Double {
        switch self {
        case .hour:  1.0 / 24
        case .day:   0.25
        case .week:  1.0
        case .month: 5.0
        }
    }

    /// How far the Crown can travel in each direction, in days. Roughly two turns of useful
    /// range in every mode: far enough to be worth scrubbing, short enough that the value does
    /// not run away from you.
    var range: Double {
        switch self {
        case .hour:  2
        case .day:   60
        case .week:  366
        case .month: 1830
        }
    }

    var label: String {
        switch self {
        case .hour:  "1h"
        case .day:   "6h"
        case .week:  "1d"
        case .month: "5d"
        }
    }

    var next: ScrubStep {
        ScrubStep(rawValue: (rawValue + 1) % ScrubStep.allCases.count) ?? .hour
    }

    /// Whether the scrubbed date should show a time as well as a day — pointless in month steps,
    /// essential in hour steps.
    var showsTime: Bool { self == .hour || self == .day }
}
