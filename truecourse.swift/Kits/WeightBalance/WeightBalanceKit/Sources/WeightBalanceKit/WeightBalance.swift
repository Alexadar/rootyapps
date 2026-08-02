import Foundation

/// A loading station: a weight (lb) at an arm (inches aft of datum).
public struct Station: Sendable, Equatable, Identifiable {
    public let id: Int
    public var name: String
    public var weightLb: Double
    public var armIn: Double

    public init(id: Int = 0, name: String = "", weightLb: Double, armIn: Double) {
        self.id = id; self.name = name; self.weightLb = weightLb; self.armIn = armIn
    }

    /// Moment (lb·in) contributed by this station.
    public var momentLbIn: Double { weightLb * armIn }
}

/// A vertex of the CG envelope, expressed as (CG inches, weight lb).
public struct EnvelopePoint: Sendable, Equatable {
    public let cgIn: Double
    public let weightLb: Double
    public init(cgIn: Double, weightLb: Double) { self.cgIn = cgIn; self.weightLb = weightLb }
}

/// Weight & balance math for the E6B flight computer.
public enum WeightBalance {

    /// Moment (lb·in) = weight × arm.
    public static func moment(weightLb: Double, armIn: Double) -> Double { weightLb * armIn }

    /// Totals and centre of gravity for a set of loading stations.
    public static func cg(stations: [Station]) -> (totalWeightLb: Double, totalMomentLbIn: Double, cgIn: Double) {
        let w = stations.reduce(0) { $0 + $1.weightLb }
        let m = stations.reduce(0) { $0 + $1.momentLbIn }
        return (w, m, w != 0 ? m / w : 0)
    }

    /// Is the loaded (CG, weight) point inside the envelope polygon? Ray-casting test;
    /// the envelope vertices are taken in order (closed automatically).
    public static func withinEnvelope(cgIn: Double, weightLb: Double, envelope: [EnvelopePoint]) -> Bool {
        guard envelope.count >= 3 else { return false }
        var inside = false
        var j = envelope.count - 1
        for i in 0..<envelope.count {
            let xi = envelope[i].cgIn, yi = envelope[i].weightLb
            let xj = envelope[j].cgIn, yj = envelope[j].weightLb
            if ((yi > weightLb) != (yj > weightLb)),
               cgIn < (xj - xi) * (weightLb - yi) / (yj - yi) + xi {
                inside.toggle()
            }
            j = i
        }
        return inside
    }
}
