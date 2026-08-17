import Foundation

/// How hard a district is, measured rather than declared.
///
/// PROMPT.md §4: "difficulty is measured, not guessed — grade a block by minimum jumps and by
/// margin. A jump needing 98% of max power is hard; one needing 40% is not." Everything here is
/// read off the solver's own output, which means the difficulty curve and the solvability guarantee
/// cannot disagree with each other.
public struct DifficultyGrade: Hashable, Codable, Sendable {
    /// Length of the shortest route from spawn to goal. Shown to the player as par.
    public let minJumps: Int
    /// Margin on the tightest jump of that route. 0.02 means the player has 2% of the envelope
    /// to spare on the hardest thing the district asks of them.
    public let tightestMargin: Double
    public let medianMargin: Double
    /// Narrowest target on the par route, radians. The difficulty axis that did not exist in 1-D:
    /// a far, small roof can sit comfortably inside the power envelope and still demand precise aim.
    public let tightestAngularWidth: Double
    /// Mean onward options. 1.0 is a corridor, not a block.
    public let meanBranchingFactor: Double
    /// How many jumps the fly saves. 0 means the fly is decoration in this district.
    public let flyShortcutJumps: Int
    public let band: Band

    public enum Band: String, Codable, Sendable, CaseIterable {
        case gentle, steady, tight, brutal

        /// Bands are defined by the margin on the hardest required jump, because that is what the
        /// player's thumb actually experiences. The boundaries are deliberately coarse: this is a
        /// dial for pacing districts, not a scoring system.
        static func forMargin(_ m: Double) -> Band {
            switch m {
            case ..<0.12: return .brutal
            case ..<0.28: return .tight
            case ..<0.50: return .steady
            default: return .gentle
            }
        }
    }

    public static func grade(_ block: CityBlock, in w: WorldConfig,
                             using prebuilt: ReachabilityGraph? = nil) -> DifficultyGrade? {
        // The caller usually already has the base graph; building the adjacency cube is the
        // expensive part, so it is threaded through rather than recomputed.
        let base = prebuilt ?? ReachabilityGraph(block: block, config: w)
        guard let route = base.route(from: block.spawn, to: block.goal) else { return nil }

        let margins = route.steps.map(\.margin).sorted()
        let median = margins.isEmpty ? 1.0 : margins[margins.count / 2]

        let boostedGraph = ReachabilityGraph(block: block, config: w, boosted: true)
        let boostedJumps = boostedGraph.route(from: block.spawn, to: block.goal)?.jumpCount
            ?? route.jumpCount

        return DifficultyGrade(
            minJumps: route.jumpCount,
            tightestMargin: route.tightestMargin,
            medianMargin: median,
            tightestAngularWidth: route.tightestAngularWidth,
            meanBranchingFactor: base.meanBranchingFactor,
            flyShortcutJumps: max(0, route.jumpCount - boostedJumps),
            band: Band.forMargin(route.tightestMargin)
        )
    }
}

/// The shipping gate. Nothing reaches the renderer that has not returned `.cleared`.
public enum Verdict: Equatable, Sendable {
    case cleared(DifficultyGrade)
    case goalUnreachable
    case trapRoofs([RooftopID])
    case corridor(Double)
    case aimTooTight(Double)
    case degenerate(String)

    public var isCleared: Bool { if case .cleared = self { return true }; return false }
    public var grade: DifficultyGrade? { if case .cleared(let g) = self { return g }; return nil }
}
