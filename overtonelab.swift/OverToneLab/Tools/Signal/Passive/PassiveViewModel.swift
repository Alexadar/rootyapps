import Foundation
import Combine
import PassiveKit

@MainActor
final class PassiveViewModel: ObservableObject {
    // RC (R in kΩ, C in µF)
    @Published var rcR = 1.0
    @Published var rcC = 1.0
    var rcHz: Double { Passive.rcCutoffHz(resistanceOhms: rcR * 1000, capacitanceFarads: rcC * 1e-6) }

    // RL (R in kΩ, L in mH)
    @Published var rlR = 1.0
    @Published var rlL = 10.0
    var rlHz: Double { Passive.rlCutoffHz(resistanceOhms: rlR * 1000, inductanceHenries: rlL * 1e-3) }

    // LC (L in mH, C in µF)
    @Published var lcL = 1.0
    @Published var lcC = 1.0
    var lcHz: Double { Passive.lcResonanceHz(inductanceHenries: lcL * 1e-3, capacitanceFarads: lcC * 1e-6) }
}
