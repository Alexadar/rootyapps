import Foundation

public struct RooftopID: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public let rawValue: Int
    public init(_ rawValue: Int) { self.rawValue = rawValue }
    public static func < (a: RooftopID, b: RooftopID) -> Bool { a.rawValue < b.rawValue }
    public var description: String { "r\(rawValue)" }
}

/// A rooftop: a landing surface at a height, which is all the solver needs to know about a building.
///
/// The building below it is scenery. Froggo 1's towers were 1100–1300 points tall so that falling
/// off read as falling a long way; none of that height is reachable or interactive, and none of it
/// belongs in the solver.
public struct Rooftop: Hashable, Codable, Sendable {
    public let id: RooftopID
    /// The roof surface on the ground plane.
    public let footprint: Rect2
    /// Height of the roof surface.
    public let height: Double

    public init(id: RooftopID, footprint: Rect2, height: Double) {
        self.id = id
        self.footprint = footprint
        self.height = height
    }

    public var center: Vec3 { Vec3(footprint.center.x, height, footprint.center.z) }

    /// Where the frog stands after landing near `p`.
    ///
    /// The frog is recentred onto the roof after it settles. That is not cosmetic tidiness — it is
    /// what makes the solver's model true. If the frog could come to rest anywhere on a roof, then
    /// "can I get from here to there" would depend on a continuous position and the reachability
    /// graph would not be finite. Recentring collapses the state space to one node per roof, which
    /// is precisely the assumption every property in this Kit is stated under.
    public func standingPosition() -> Vec3 { center }
}

/// One district: the rooftops, where the player starts, and where they are trying to get to.
public struct CityBlock: Hashable, Codable, Sendable {
    public let seed: UInt64
    public let districtIndex: Int
    /// Always sorted by id. The ordering is load-bearing: it is what makes the JSON encoding a
    /// usable determinism assertion.
    public let rooftops: [Rooftop]
    public let spawn: RooftopID
    public let goal: RooftopID
    /// Roofs carrying a fly. Every one is reachable without a fly — a pickup you cannot reach is
    /// not a pickup.
    public let flyRoofs: [RooftopID]
    /// Falling below this ends the run. Froggo 1 used an absolute `pitHeight = 600`, which cannot
    /// survive into a game where districts stack at different heights.
    public let killPlaneY: Double

    public init(seed: UInt64, districtIndex: Int, rooftops: [Rooftop],
                spawn: RooftopID, goal: RooftopID, flyRoofs: [RooftopID], killPlaneY: Double) {
        self.seed = seed
        self.districtIndex = districtIndex
        self.rooftops = rooftops.sorted { $0.id < $1.id }
        self.spawn = spawn
        self.goal = goal
        self.flyRoofs = flyRoofs.sorted()
        self.killPlaneY = killPlaneY
    }

    public subscript(id: RooftopID) -> Rooftop {
        guard let r = rooftops.first(where: { $0.id == id }) else {
            preconditionFailure("rooftop \(id) is not in block \(seed)")
        }
        return r
    }

    public var count: Int { rooftops.count }

    public var lowestRoofHeight: Double { rooftops.map(\.height).min() ?? 0 }
    public var highestRoofHeight: Double { rooftops.map(\.height).max() ?? 0 }
}
