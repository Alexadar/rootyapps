import Foundation

/// Thiele-Small loudspeaker driver parameters.
public struct Driver: Sendable, Equatable {
    public var fsHz: Double     // free-air resonance
    public var qts: Double      // total Q at resonance
    public var vasLiters: Double // equivalent compliance volume
    public init(fsHz: Double, qts: Double, vasLiters: Double) {
        self.fsHz = fsHz; self.qts = qts; self.vasLiters = vasLiters
    }
}

/// Sealed (closed-box) alignment. Pure, stateless. Standard Small closed-box theory.
public enum Sealed {
    /// Compliance ratio α = Vas / Vb.
    public static func alpha(vasLiters vas: Double, vbLiters vb: Double) -> Double {
        guard vb > 0 else { return 0 }
        return vas / vb
    }
    /// System Q in the box: Qtc = Qts·√(α+1).
    public static func qtc(_ d: Driver, vbLiters vb: Double) -> Double {
        d.qts * (alpha(vasLiters: d.vasLiters, vbLiters: vb) + 1).squareRoot()
    }
    /// System resonance: Fc = Fs·√(α+1).
    public static func fcHz(_ d: Driver, vbLiters vb: Double) -> Double {
        d.fsHz * (alpha(vasLiters: d.vasLiters, vbLiters: vb) + 1).squareRoot()
    }
    /// −3 dB frequency of a 2nd-order closed box:
    /// F3 = Fc·√[ ((1/Qtc²−2) + √((1/Qtc²−2)²+4)) / 2 ].  (For Qtc=0.707 this gives F3 = Fc.)
    public static func f3Hz(_ d: Driver, vbLiters vb: Double) -> Double {
        let fc = fcHz(d, vbLiters: vb), q = qtc(d, vbLiters: vb)
        guard q > 0 else { return 0 }
        let a = 1 / (q * q) - 2
        return fc * ((a + (a * a + 4).squareRoot()) / 2).squareRoot()
    }
    /// Box volume needed to hit a target Qtc: Vb = Vas / ((Qtc/Qts)² − 1).
    public static func vbForQtc(_ d: Driver, targetQtc qtc: Double) -> Double {
        let r = (qtc / d.qts) * (qtc / d.qts) - 1
        guard r > 0 else { return .infinity }
        return d.vasLiters / r
    }
}

/// Vented (bass-reflex) box: port length for a target tuning. Pure, stateless.
public enum Ported {
    /// Port length (m) for a Helmholtz tuning Fb, box volume Vb, port diameter d and count N.
    /// Lv = c²·N·π(d/2)² / (4π²·Vb·Fb²) − 0.732·d   (0.732·d = combined port end correction).
    /// Matches the classic Small/JBL port formula (c = 344 m/s).
    public static func portLengthM(tuningHz fb: Double, boxVolumeM3 vb: Double,
                                   portDiameterM d: Double, ports n: Int = 1, speed c: Double = 344) -> Double {
        guard fb > 0, vb > 0, d > 0 else { return 0 }
        let av = Double(n) * .pi * pow(d / 2, 2)
        let leff = c * c * av / (4 * .pi * .pi * vb * fb * fb)
        return leff - 0.732 * d
    }
}
