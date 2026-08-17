import SwiftUI
import DocumentModelKit

// GridScan design tokens — adopted from the approved CD mockups (design/swift-mockups).
enum GS {
    static let tint = Color.accentColor
    static let corrected = Color(red: 0.345, green: 0.337, blue: 0.839)   // #5856D6
    static let flag = Color.orange
    static let flagText = Color(red: 0.788, green: 0.204, blue: 0.0)      // #C93400

    static let hitTarget: CGFloat = 44
    static let gridRowHeight: CGFloat = 36
    static let tileRadius: CGFloat = 12
    static let sheetRadius: CGFloat = 16

    /// Opaque data/paper surface — documents and grids are never glass.
    static var surface: Color {
#if canImport(UIKit)
        Color(.secondarySystemGroupedBackground)
#else
        Color(nsColor: .controlBackgroundColor)
#endif
    }
}

// Structural kind is FIRST-CLASS (tier one). Kinds describe layout SHAPE, never
// content meaning. The model type is the Kit's; presentation lives here.
extension DocumentKind {
    var symbolName: String {
        switch self {
        case .table: return "tablecells"
        case .form: return "list.bullet.rectangle"
        case .report: return "doc.text"
        }
    }

    var displayName: String { rawValue.capitalized }
}

/// Cell presentation state, derived from the flag sidecar — never from a confidence
/// field on the data (none exists). Legitimate states only.
enum CellState: Equatable {
    case plain
    case corrected(was: String)
    case flagged(reason: FlagReason)

    var isFlagged: Bool { if case .flagged = self { return true }; return false }
}

extension FlagReason {
    var spokenDescription: String {
        switch self {
        case .failedFormatRule(let rule): return "failed format rule: \(rule)"
        case .lowOCRConfidence: return "low confidence text, verify against the page"
        case .missingRequired: return "missing required field"
        }
    }
}
