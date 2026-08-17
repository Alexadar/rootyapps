import Foundation

/// Adiabatic mixing of airstreams.
public enum AirMixing {

    /// One stream entering the mix: a state and a volumetric flow, m³/s.
    public struct Stream: Equatable, Sendable {
        public let state: MoistAir
        /// Volumetric flow rate, m³/s. Convert from CFM at the app edge.
        public let volumeFlow: Double

        public init(state: MoistAir, volumeFlow: Double) {
            self.state = state
            self.volumeFlow = volumeFlow
        }

        /// Mass flow of **dry air**, kg/s — volumetric flow over specific volume.
        ///
        /// This, not the volumetric flow, is what mixes. Weighting by CFM is the common shortcut
        /// and it is wrong wherever the two streams differ in density, which is exactly the case
        /// the tool exists for: 20 °F outdoor air against 75 °F return air differ by 11 %, and at
        /// altitude the error compounds.
        public var dryAirMassFlow: Double { volumeFlow / state.specificVolume }
    }

    /// Mix two airstreams adiabatically.
    ///
    /// Humidity ratio and enthalpy are conserved on a dry-air mass basis; the mixed dry bulb falls
    /// out of the mixed enthalpy and humidity ratio. The mixed point lies on the straight line
    /// between the two inputs on the chart, at the ratio of their dry-air mass flows.
    ///
    /// - Throws: ``PsychroError/supersaturated(humidityRatio:saturation:)`` when the mix lands
    ///   below the saturation curve — the streams fog when combined, which is a real answer and
    ///   not one to round away.
    public static func mix(_ a: Stream, _ b: Stream) throws -> MoistAir {
        try mix([a, b])
    }

    /// Mix any number of airstreams adiabatically.
    public static func mix(_ streams: [Stream]) throws -> MoistAir {
        guard let first = streams.first else { throw PsychroError.unsolvable }
        let pressure = first.state.pressure
        guard streams.allSatisfy({ abs($0.state.pressure - pressure) < 1e-6 }) else {
            throw PsychroError.pressureOutOfRange(pressure)
        }
        guard streams.allSatisfy({ $0.volumeFlow.isFinite && $0.volumeFlow >= 0 }) else {
            throw PsychroError.unsolvable
        }

        let totalMass = streams.reduce(0) { $0 + $1.dryAirMassFlow }
        guard totalMass > 0 else { throw PsychroError.unsolvable }

        let w = streams.reduce(0) { $0 + $1.dryAirMassFlow * $1.state.humidityRatio } / totalMass
        let h = streams.reduce(0) { $0 + $1.dryAirMassFlow * $1.state.enthalpy } / totalMass
        let t = Psychrometrics.dryBulb(enthalpy: h, humidityRatio: w)

        return try MoistAir(dryBulb: t, humidityRatio: w, pressure: pressure)
    }

    /// The fraction of the mixed dry-air mass contributed by `stream`, 0…1 — the outdoor-air
    /// fraction, when `stream` is the outdoor air.
    public static func massFraction(of stream: Stream, in streams: [Stream]) -> Double {
        let total = streams.reduce(0) { $0 + $1.dryAirMassFlow }
        return total > 0 ? stream.dryAirMassFlow / total : 0
    }
}
