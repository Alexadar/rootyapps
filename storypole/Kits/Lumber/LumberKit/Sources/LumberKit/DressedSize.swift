import Foundation
import DimensionKit

/// Nominal vs dressed lumber sizes — why a "2×4" measures 1½″ × 3½″.
///
/// Pure, stateless.
///
/// ## Oracle: PUBLISHED
///
/// NIST **PS 20-20** Table 3, *"Nominal and minimum-dressed sizes of boards, dimension, and
/// timbers"* (US Government work, public domain). Transcribed verbatim; the millimetre column is
/// reproduced independently in `LumberKitTests` from 25.4 mm/in under the App. B §B1 rounding rule,
/// which is round-half-to-even.
///
/// https://www.nist.gov/document/doc-ps-20-20-american-softwood-lumber-standard — retrieved
/// 2026-07-29, HTTP 200.
///
/// PS 20-20 §3.4.4 is worth quoting for the Reference screen, because it is the whole point:
/// > *"The use of 'nominal' sizes in the language of this Standard follows the practice of the
/// > industry. No inferences shall be drawn that the 'nominal' sizes are dressed sizes."*
public enum DressedSize {

    /// Lumber is dressed to a smaller size when green than when dry, because it shrinks as it dries.
    /// PS 20-20 Table 3 tabulates both columns.
    public enum Seasoning: String, CaseIterable, Sendable {
        case dry, green
    }

    /// One row of PS 20-20 Table 3.
    public struct Row: Equatable, Sendable {
        public let nominalIn: Rational
        public let dryIn: Rational
        public let greenIn: Rational
        /// The millimetre value the standard prints for the DRY dressed size.
        public let dryMM: Int

        public func dressed(_ s: Seasoning) -> Rational { s == .dry ? dryIn : greenIn }
    }

    /// PS 20-20 Table 3, transcribed. Nominal → minimum dressed, dry and green, in inches.
    ///
    /// Note the two families in the standard share these values: "Boards" for the thin stock and
    /// "Dimension" for framing. The 2 → 1½ and 4 → 3½ rows are the ones everyone knows.
    public static let table: [Row] = [
        Row(nominalIn: Rational(3, 8),  dryIn: Rational(5, 16),  greenIn: Rational(11, 32), dryMM: 8),
        Row(nominalIn: Rational(1, 2),  dryIn: Rational(7, 16),  greenIn: Rational(15, 32), dryMM: 11),
        Row(nominalIn: Rational(5, 8),  dryIn: Rational(9, 16),  greenIn: Rational(19, 32), dryMM: 14),
        Row(nominalIn: Rational(3, 4),  dryIn: Rational(5, 8),   greenIn: Rational(11, 16), dryMM: 16),
        Row(nominalIn: Rational(1),     dryIn: Rational(3, 4),   greenIn: Rational(25, 32), dryMM: 19),
        Row(nominalIn: Rational(5, 4),  dryIn: Rational(1),      greenIn: Rational(33, 32), dryMM: 25),
        Row(nominalIn: Rational(3, 2),  dryIn: Rational(5, 4),   greenIn: Rational(41, 32), dryMM: 32),
        Row(nominalIn: Rational(2),     dryIn: Rational(3, 2),   greenIn: Rational(25, 16), dryMM: 38),
        Row(nominalIn: Rational(5, 2),  dryIn: Rational(2),      greenIn: Rational(33, 16), dryMM: 51),
        Row(nominalIn: Rational(3),     dryIn: Rational(5, 2),   greenIn: Rational(41, 16), dryMM: 64),
        Row(nominalIn: Rational(7, 2),  dryIn: Rational(3),      greenIn: Rational(49, 16), dryMM: 76),
        Row(nominalIn: Rational(4),     dryIn: Rational(7, 2),   greenIn: Rational(57, 16), dryMM: 89),
        Row(nominalIn: Rational(9, 2),  dryIn: Rational(4),      greenIn: Rational(65, 16), dryMM: 102),
        Row(nominalIn: Rational(5),     dryIn: Rational(9, 2),   greenIn: Rational(37, 8),  dryMM: 114),
        Row(nominalIn: Rational(6),     dryIn: Rational(11, 2),  greenIn: Rational(45, 8),  dryMM: 140),
        Row(nominalIn: Rational(7),     dryIn: Rational(13, 2),  greenIn: Rational(53, 8),  dryMM: 165),
        Row(nominalIn: Rational(8),     dryIn: Rational(29, 4),  greenIn: Rational(15, 2),  dryMM: 184),
        Row(nominalIn: Rational(9),     dryIn: Rational(33, 4),  greenIn: Rational(17, 2),  dryMM: 210),
        Row(nominalIn: Rational(10),    dryIn: Rational(37, 4),  greenIn: Rational(19, 2),  dryMM: 235),
        Row(nominalIn: Rational(11),    dryIn: Rational(41, 4),  greenIn: Rational(21, 2),  dryMM: 260),
        Row(nominalIn: Rational(12),    dryIn: Rational(45, 4),  greenIn: Rational(23, 2),  dryMM: 286),
        Row(nominalIn: Rational(14),    dryIn: Rational(53, 4),  greenIn: Rational(27, 2),  dryMM: 337),
        Row(nominalIn: Rational(16),    dryIn: Rational(61, 4),  greenIn: Rational(31, 2),  dryMM: 387),
    ]

    /// The dressed size for a nominal dimension, or `nil` if the standard does not tabulate it.
    /// `nil` rather than a guess: an untabulated size has no published dressed dimension.
    public static func dressed(nominalIn n: Rational, seasoning: Seasoning = .dry) -> Rational? {
        table.first { $0.nominalIn == n }?.dressed(seasoning)
    }

    /// The dressed size as a `FeetInch`. Named distinctly from `dressed(nominalIn:seasoning:)`
    /// because two overloads differing only in return type are ambiguous at every call site.
    public static func dressedDimension(nominalIn n: Rational, seasoning: Seasoning = .dry) -> FeetInch? {
        dressed(nominalIn: n, seasoning: seasoning).map { FeetInch(inches: $0) }
    }

    /// The dressed section of a nominal piece, e.g. `2×4` → `(1½", 3½")`.
    public static func section(nominalThicknessIn t: Rational, nominalWidthIn w: Rational,
                               seasoning: Seasoning = .dry) -> (thickness: FeetInch, width: FeetInch)? {
        guard let dt = dressed(nominalIn: t, seasoning: seasoning),
              let dw = dressed(nominalIn: w, seasoning: seasoning) else { return nil }
        return (FeetInch(inches: dt), FeetInch(inches: dw))
    }

    /// How much of the nominal cross-section actually arrives, as a fraction. A 2×4 is 65.6 %.
    /// This is the number that makes the board-foot CAUTION concrete.
    public static func dressedSectionFraction(nominalThicknessIn t: Rational, nominalWidthIn w: Rational,
                                              seasoning: Seasoning = .dry) -> Rational? {
        guard let dt = dressed(nominalIn: t, seasoning: seasoning),
              let dw = dressed(nominalIn: w, seasoning: seasoning) else { return nil }
        return (dt * dw) / (t * w)
    }

    /// PS 20-20 §3.4.4, for the Reference screen.
    public static let nominalDisclaimer = """
        The use of "nominal" sizes in the language of this Standard follows the practice of the \
        industry. No inferences shall be drawn that the "nominal" sizes are dressed sizes. \
        — NIST PS 20-20 §3.4.4
        """
}
