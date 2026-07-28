import Foundation

/// Unit system a station's heights are expressed in.
///
/// The Kit computes in whatever units the station's constants carry — NOAA
/// publishes both, and the feet path is oracle-tested against NOAA's *own*
/// English-unit predictions rather than against a conversion of the metric ones.
public enum TideUnit: String, Sendable, CaseIterable {
    case meters, feet

    /// Exact international foot: 1 ft = 0.3048 m.
    public static let metersPerFoot = 0.3048

    public func toMeters(_ value: Double) -> Double {
        switch self {
        case .meters: return value
        case .feet:   return value * TideUnit.metersPerFoot
        }
    }

    public func toFeet(_ value: Double) -> Double {
        switch self {
        case .meters: return value / TideUnit.metersPerFoot
        case .feet:   return value
        }
    }
}

/// One harmonic constituent of a station: amplitude H and Greenwich epoch G.
///
/// `amplitude` is in the station's `TideUnit`. `greenwichPhaseDeg` is NOAA's
/// `phase_GMT` (Schureman's *G*, referred to the Greenwich meridian).
public struct Constituent: Sendable, Equatable {
    public var definition: ConstituentDefinition
    public var amplitude: Double
    public var greenwichPhaseDeg: Double

    public init(definition: ConstituentDefinition, amplitude: Double, greenwichPhaseDeg: Double) {
        precondition(amplitude >= 0, "constituent amplitude must be >= 0")
        self.definition = definition
        self.amplitude = amplitude
        self.greenwichPhaseDeg = greenwichPhaseDeg
    }

    /// Convenience initialiser from a NOAA constituent name.
    public init?(name: String, amplitude: Double, greenwichPhaseDeg: Double) {
        guard let def = Constituents.named(name) else { return nil }
        self.init(definition: def, amplitude: amplitude, greenwichPhaseDeg: greenwichPhaseDeg)
    }

    public var name: String { definition.id.rawValue }
    public var speedDegPerHour: Double { definition.speedDegPerHour }
}

/// A tide station: its datum offset and harmonic constants.
///
/// `meanWaterLevel` is Z₀ — the height of mean sea level above the prediction
/// datum. For NOAA chart-datum (MLLW) predictions this is `MSL − MLLW`, because
/// the published constituent amplitudes are referred to MSL while the published
/// predictions are referred to MLLW.
public struct Station: Sendable, Equatable {
    public var id: String
    public var name: String
    public var latitudeDeg: Double
    public var longitudeDeg: Double
    public var unit: TideUnit
    public var meanWaterLevel: Double
    public var constituents: [Constituent]

    public init(id: String, name: String,
                latitudeDeg: Double = .nan, longitudeDeg: Double = .nan,
                unit: TideUnit, meanWaterLevel: Double, constituents: [Constituent]) {
        self.id = id
        self.name = name
        self.latitudeDeg = latitudeDeg
        self.longitudeDeg = longitudeDeg
        self.unit = unit
        self.meanWaterLevel = meanWaterLevel
        self.constituents = constituents
    }
}

public enum TideKind: String, Sendable {
    case high = "High", low = "Low"
}

/// A predicted high or low water.
public struct TideEvent: Sendable, Equatable {
    public var date: Date
    public var height: Double
    public var unit: TideUnit
    public var kind: TideKind

    public init(date: Date, height: Double, unit: TideUnit, kind: TideKind) {
        self.date = date; self.height = height; self.unit = unit; self.kind = kind
    }
}

/// A tidal-current station: constants for the major-axis velocity.
///
/// NOAA publishes current constants with a different shape from height constants:
/// `majorAmplitude` (cm/s) and `majorPhaseGMT`, plus the mean flood/ebb directions.
public struct CurrentStation: Sendable, Equatable {
    public var id: String
    public var name: String
    public var bin: Int
    /// Mean flood direction, degrees true.
    public var meanFloodDirectionDeg: Double
    /// Mean ebb direction, degrees true.
    public var meanEbbDirectionDeg: Double
    /// Non-tidal mean flow along the major axis, cm/s (0 if unknown).
    public var meanFlowCMS: Double
    public var constituents: [Constituent]

    public init(id: String, name: String, bin: Int = 1,
                meanFloodDirectionDeg: Double, meanEbbDirectionDeg: Double,
                meanFlowCMS: Double = 0, constituents: [Constituent]) {
        self.id = id; self.name = name; self.bin = bin
        self.meanFloodDirectionDeg = meanFloodDirectionDeg
        self.meanEbbDirectionDeg = meanEbbDirectionDeg
        self.meanFlowCMS = meanFlowCMS
        self.constituents = constituents
    }
}

public enum CurrentPhase: String, Sendable {
    case slack = "Slack", flood = "Flood", ebb = "Ebb"
}

/// A predicted slack water or maximum flood/ebb.
public struct CurrentEvent: Sendable, Equatable {
    public var date: Date
    /// Signed major-axis velocity, cm/s. Positive = flood, negative = ebb.
    public var velocityCMS: Double
    public var phase: CurrentPhase

    public init(date: Date, velocityCMS: Double, phase: CurrentPhase) {
        self.date = date; self.velocityCMS = velocityCMS; self.phase = phase
    }

    /// Direction of the flow, degrees true, given the station's mean axes.
    public func directionDeg(_ station: CurrentStation) -> Double? {
        switch phase {
        case .slack: return nil
        case .flood: return station.meanFloodDirectionDeg
        case .ebb:   return station.meanEbbDirectionDeg
        }
    }
}
