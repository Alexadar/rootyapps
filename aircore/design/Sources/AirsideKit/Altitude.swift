import Foundation

/// Altitude / elevation correction — a first-class input, never a buried setting.
/// Barometric pressure from the ISA troposphere model.
public struct Altitude: Equatable, Sendable {
    public var feet: Double
    public init(feet: Double) { self.feet = feet }

    public static let seaLevel = Altitude(feet: 0)
    public static let denver = Altitude(feet: 5280)
    public static let mexicoCity = Altitude(feet: 7350)

    /// Local barometric pressure, Pa.
    public var pressurePa: Double {
        let z = Convert.ftToM(feet)
        return 101_325.0 * pow(1 - 2.25577e-5 * z, 5.2559)
    }

    /// Air-side sensible constant (sea-level 1.08) scaled for local density.
    public var sensibleConstant: Double { 1.08 * pressurePa / 101_325.0 }
    /// Latent constant (sea-level 4840).
    public var latentConstant: Double { 4840.0 * pressurePa / 101_325.0 }
    /// Total constant (sea-level 4.5).
    public var totalConstant: Double { 4.5 * pressurePa / 101_325.0 }
}
