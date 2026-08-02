import Foundation

/// Segmented-picker option tables for the pipe tools, kept **out of the views** so the
/// index → value mapping is unit-testable. A wrong row here would silently feed the wrong angle or
/// grade into an otherwise-correct Kit call — the same class of bug `ToolHeroes` exists to prevent.
/// See `kerfcalcTests/PipeOptionsTests.swift`.

/// Standard fitting angles a fitter actually buys, plus a custom entry.
enum PipeFittingChoice {
    static let titles = ["45°", "22½°", "11¼°", "Other"]
    static let otherIndex = 3

    /// Degrees for the picked segment; `custom` is used only for the "Other" row.
    static func angleDeg(index: Int, custom: Double) -> Double {
        switch index {
        case 0: return 45
        case 1: return 22.5
        case 2: return 11.25
        default: return custom
        }
    }
}

/// Drainage grades the codes and drawings actually name, plus a custom entry.
enum PipeGradeChoice {
    static let titles = ["¼\"/ft", "⅛\"/ft", "½\"/ft", "Other"]
    static let otherIndex = 3

    /// Fall in inches per foot for the picked segment; `custom` is used only for "Other".
    static func fallInPerFt(index: Int, custom: Double) -> Double {
        switch index {
        case 0: return 0.25
        case 1: return 0.125
        case 2: return 0.5
        default: return custom
        }
    }
}
