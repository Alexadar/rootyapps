import Foundation

/// Weight of a length of pipe from its own dimensions. Pure, stateless. Lengths in inches unless a
/// label says otherwise.
///
/// A pipe is a hollow cylinder, so the metal's cross-section reduces to a tidy closed form:
///
///     area = π⁄4 · (OD² − ID²),  ID = OD − 2t   ⟹   area = π · (OD − t) · t
///     lb/ft = area · 12 · density
///
/// That reproduces the pipefitter's published steel rule **lb/ft = 10.68 · (OD − t) · t** exactly, since
/// `π · 12 · 0.2836 lb/in³ = 10.6896` — an identity oracle for a number the trade prints in tables
/// (see PipeWeightOracleTests). Because the constant falls out of the density, no table is shipped.
///
/// **Density is user-entered and NOT oracle-backed** — it is a material property the user supplies
/// (carbon steel ≈ 0.2836 lb/in³, copper ≈ 0.323, PVC ≈ 0.051). Contents are not included: this is the
/// weight of the pipe wall only, empty.
public enum PipeWeight {

    /// Cross-sectional area of the pipe *wall* — `π · (OD − t) · t`, in².
    /// Returns 0 for a wall that is missing, negative, or thick enough to close the bore.
    public static func wallAreaIn2(odIn: Double, wallIn: Double) -> Double {
        guard odIn > 0, wallIn > 0, wallIn < odIn / 2 else { return 0 }
        return Double.pi * (odIn - wallIn) * wallIn
    }

    /// Weight per foot — `wallArea · 12 · density`, lb/ft.
    public static func weightLbPerFt(odIn: Double, wallIn: Double, densityLbPerIn3: Double) -> Double {
        wallAreaIn2(odIn: odIn, wallIn: wallIn) * 12 * densityLbPerIn3
    }

    /// Weight of a run of pipe, lb.
    public static func weightLb(lengthFt: Double, odIn: Double, wallIn: Double,
                                densityLbPerIn3: Double) -> Double {
        weightLbPerFt(odIn: odIn, wallIn: wallIn, densityLbPerIn3: densityLbPerIn3) * lengthFt
    }

    /// Inside diameter — `OD − 2t`, in. 0 once the wall closes the bore.
    public static func idIn(odIn: Double, wallIn: Double) -> Double {
        let id = odIn - 2 * wallIn
        return id > 0 ? id : 0
    }
}
