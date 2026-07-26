import Testing
import Foundation
@testable import ThieleKit

/// Oracles (external, cited):
///  • Small closed-box theory: Qtc = Qts·√(α+1), Fc = Fs·√(α+1); the Butterworth (Qtc=0.707)
///    alignment has F3 = Fc exactly (Small, "Closed-Box Loudspeaker Systems").
///  • Classic Small/JBL vented port-length formula (Dickason, *Loudspeaker Design Cookbook*).
@Suite struct ThieleOracle {
    let driver = Driver(fsHz: 25, qts: 0.4, vasLiters: 100)

    @Test func sealedButterworthAlignment() {
        // Vb for a maximally-flat Qtc = 0.707.
        let vb = Sealed.vbForQtc(driver, targetQtc: 0.7071)
        #expect(abs(vb - 47.08) < 0.2)                       // textbook ≈ 47 L
        // That box reproduces Qtc = 0.707 (round-trip through the forward equations).
        #expect(abs(Sealed.qtc(driver, vbLiters: vb) - 0.7071) < 1e-3)
        // Butterworth identity: F3 == Fc.
        let fc = Sealed.fcHz(driver, vbLiters: vb)
        #expect(abs(Sealed.f3Hz(driver, vbLiters: vb) - fc) < 1e-2)
        #expect(abs(fc - 44.19) < 0.2)                       // Fs·√(α+1)
    }

    @Test func sealedMonotonic() {
        // Smaller box → higher Qtc and higher Fc (stiffer air spring).
        #expect(Sealed.qtc(driver, vbLiters: 20) > Sealed.qtc(driver, vbLiters: 80))
        #expect(Sealed.fcHz(driver, vbLiters: 20) > Sealed.fcHz(driver, vbLiters: 80))
        // Qtc = 1.0 peaks: F3 below Fc (factor ≈ 0.786).
        let vb1 = Sealed.vbForQtc(driver, targetQtc: 1.0)
        #expect(abs(Sealed.f3Hz(driver, vbLiters: vb1) / Sealed.fcHz(driver, vbLiters: vb1) - 0.786) < 0.01)
    }

    @Test func ventedPortLengthVsClassicFormula() {
        // 50 L box tuned to 35 Hz with one 10 cm port.
        let lv = Ported.portLengthM(tuningHz: 35, boxVolumeM3: 0.05, portDiameterM: 0.10, ports: 1)
        // Classic: Lv(cm) = 23562.5·d²·N/(Fb²·Vb_L) − 0.732·d  ≈ 31.15 cm.
        let dCm = 10.0, fb = 35.0, vbL = 50.0
        let classicCm: Double = 23562.5 * dCm * dCm / (fb * fb * vbL) - 0.732 * dCm
        #expect(abs(lv * 100 - classicCm) < 0.3)
        #expect(abs(lv - 0.3113) < 0.003)
        // Two ports of the same diameter need a longer tube (more mass to tune the same Fb).
        let lv2 = Ported.portLengthM(tuningHz: 35, boxVolumeM3: 0.05, portDiameterM: 0.10, ports: 2)
        #expect(lv2 > lv)
    }

    @Test func guards() {
        #expect(Sealed.alpha(vasLiters: 100, vbLiters: 0) == 0)
        #expect(Ported.portLengthM(tuningHz: 0, boxVolumeM3: 0.05, portDiameterM: 0.1) == 0)
        #expect(Sealed.vbForQtc(Driver(fsHz: 25, qts: 0.8, vasLiters: 100), targetQtc: 0.5).isInfinite)
    }
}
