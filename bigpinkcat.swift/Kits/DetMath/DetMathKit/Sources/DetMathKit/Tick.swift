import Foundation

/// Simulation time, as an integer count of fixed steps.
///
/// Pure, stateless. The whole reason this is not a `Double` is that accumulating a float time is how
/// determinism dies quietly: two machines that agree on every individual step still diverge once
/// their accumulated `t` differs in the last bit, and the divergence appears hours later, in
/// a chaotic region, looking like a physics bug.
///
/// Nothing in the simulation may read a wall clock or a frame delta. The renderer interpolates
/// between ticks for display; it never tells the simulation how much time has passed.
public struct Tick: Sendable, Hashable, Comparable, CustomStringConvertible {
    public let value: Int64

    public init(_ value: Int64) { self.value = value }
    public static let zero = Tick(0)

    public static func < (a: Tick, b: Tick) -> Bool { a.value < b.value }
    public static func + (a: Tick, n: Int64) -> Tick { Tick(a.value + n) }
    public func advanced(by n: Int64 = 1) -> Tick { Tick(value + n) }

    public var description: String { "t\(value)" }

    /// Coordinate time elapsed, in geometrized units, given the step size.
    ///
    /// The multiplication happens once, from an exact integer, rather than by repeated addition —
    /// so the value at tick 10⁶ is the same whether you got there in one jump or a million steps.
    public func coordinateTime(step dt: Double) -> Double {
        Double(value) * dt
    }
}

/// The simulation's unit convention.
///
/// **Geometrized units: G = c = M = 1.** The black hole's mass is the unit of length and of time.
///
/// This is not cosmetic. It puts every quantity the integrator touches at O(1) — horizons at r ≈ 1–2,
/// the photon sphere at 3, the ISCO at 6 — which keeps the arithmetic far away from denormals (where
/// flush-to-zero behaviour differs between CPU and GPU) *and* conditions the ODE better than SI
/// units would. Two problems, one decision.
///
/// Conversions to human-facing units happen at the presentation boundary and nowhere else.
public enum Units {
    /// Solar mass in metres (GM☉/c²). ORACLE: IAU 2015 Resolution B3 nominal solar mass parameter
    /// GM☉ = 1.3271244e20 m³/s², divided by c² = 8.98755178736818e16 m²/s².
    public static let solarMassInMetres = 1.4766250382e3

    /// Convert a geometrized length (in units of M) to metres, for a hole of `solarMasses`.
    public static func metres(fromGeometrized r: Double, solarMasses: Double) -> Double {
        r * solarMassInMetres * solarMasses
    }

    /// Convert a geometrized time (in units of M) to seconds.
    public static func seconds(fromGeometrized t: Double, solarMasses: Double) -> Double {
        // In geometrized units time and length share a unit; dividing by c returns seconds.
        metres(fromGeometrized: t, solarMasses: solarMasses) / 299_792_458.0
    }
}
