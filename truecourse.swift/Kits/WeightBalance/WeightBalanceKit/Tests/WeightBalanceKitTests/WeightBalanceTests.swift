import Testing
@testable import WeightBalanceKit

// Oracle = moment arithmetic (Σmoment / Σweight) per FAA-H-8083-1 Aircraft Weight &
// Balance Handbook (https://www.faa.gov/regulations_policies/handbooks_manuals/aircraft).
// The envelope check is a point-in-polygon test against a representative light-single
// CG envelope.
@Suite("Weight & Balance — CG & envelope")
struct WeightBalanceTests {

    // A four-line loading problem with a hand-computed CG.
    let stations = [
        Station(name: "Empty",   weightLb: 1000, armIn: 36),   // 36,000
        Station(name: "Front",   weightLb: 340,  armIn: 37),   // 12,580
        Station(name: "Fuel",    weightLb: 180,  armIn: 48),   //  8,640
        Station(name: "Baggage", weightLb: 20,   armIn: 95),   //  1,900
    ]

    @Test func moment() { #expect(abs(WeightBalance.moment(weightLb: 180, armIn: 48) - 8640) < 1e-9) }

    @Test func centreOfGravity() {
        let r = WeightBalance.cg(stations: stations)
        #expect(abs(r.totalWeightLb - 1540) < 1e-9)
        #expect(abs(r.totalMomentLbIn - 59120) < 1e-9)
        #expect(abs(r.cgIn - 38.3896) < 0.001)                 // 59,120 / 1,540
    }

    // Representative envelope (CG in, weight lb): forward limit slopes aft with weight.
    let envelope = [
        EnvelopePoint(cgIn: 35.0, weightLb: 1500),
        EnvelopePoint(cgIn: 41.0, weightLb: 2550),
        EnvelopePoint(cgIn: 47.3, weightLb: 2550),
        EnvelopePoint(cgIn: 47.3, weightLb: 1500),
    ]

    @Test func loadedPointInsideEnvelope() {
        #expect(WeightBalance.withinEnvelope(cgIn: 38.39, weightLb: 1540, envelope: envelope))
    }

    @Test func outsidePointsRejected() {
        #expect(!WeightBalance.withinEnvelope(cgIn: 34.0, weightLb: 1540, envelope: envelope)) // too fwd
        #expect(!WeightBalance.withinEnvelope(cgIn: 48.0, weightLb: 1540, envelope: envelope)) // too aft
        #expect(!WeightBalance.withinEnvelope(cgIn: 40.0, weightLb: 2600, envelope: envelope)) // overweight
    }
}
