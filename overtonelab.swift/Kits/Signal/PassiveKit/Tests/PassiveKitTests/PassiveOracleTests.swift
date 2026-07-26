import Testing
import Foundation
@testable import PassiveKit

/// Oracles (external, cited) — standard passive-filter theory:
///  • RC corner f = 1/(2πRC); RL corner f = R/(2πL); LC resonance f = 1/(2π√(LC)).
@Suite struct PassiveOracle {

    @Test func rcCutoff() {
        // R = 1 kΩ, C = 1 µF → 159.155 Hz.
        #expect(abs(Passive.rcCutoffHz(resistanceOhms: 1000, capacitanceFarads: 1e-6) - 159.1549) < 1e-3)
        // Doubling C halves the corner.
        #expect(abs(Passive.rcCutoffHz(resistanceOhms: 1000, capacitanceFarads: 2e-6) - 79.577) < 1e-2)
    }

    @Test func lcAndRl() {
        // L = 1 mH, C = 1 µF → 5032.9 Hz.
        #expect(abs(Passive.lcResonanceHz(inductanceHenries: 1e-3, capacitanceFarads: 1e-6) - 5032.92) < 0.1)
        // R = 1 kΩ, L = 10 mH → 15915.5 Hz.
        #expect(abs(Passive.rlCutoffHz(resistanceOhms: 1000, inductanceHenries: 10e-3) - 15915.49) < 0.1)
    }

    @Test func guards() {
        #expect(Passive.rcCutoffHz(resistanceOhms: 0, capacitanceFarads: 1e-6) == 0)
        #expect(Passive.lcResonanceHz(inductanceHenries: 1e-3, capacitanceFarads: 0) == 0)
    }
}
