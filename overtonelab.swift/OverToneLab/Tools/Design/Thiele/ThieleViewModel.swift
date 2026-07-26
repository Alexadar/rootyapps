import Foundation
import Combine
import ThieleKit

@MainActor
final class ThieleViewModel: ObservableObject {
    // Driver (Thiele-Small)
    @Published var fs = 25.0
    @Published var qts = 0.4
    @Published var vas = 100.0
    var driver: Driver { Driver(fsHz: fs, qts: qts, vasLiters: vas) }

    var suggestedAlignment: String {
        switch qts {
        case ..<0.4: return "Low Qts — suits a vented (ported) box."
        case ..<0.6: return "Mid Qts — flexible; sealed or ported both work."
        default:     return "High Qts — suits a sealed box."
        }
    }

    // Sealed
    @Published var vb = 50.0
    var alpha: Double { Sealed.alpha(vasLiters: vas, vbLiters: vb) }
    var qtc: Double { Sealed.qtc(driver, vbLiters: vb) }
    var fc: Double { Sealed.fcHz(driver, vbLiters: vb) }
    var f3: Double { Sealed.f3Hz(driver, vbLiters: vb) }
    @Published var targetQtc = 0.707
    var vbForTarget: Double { Sealed.vbForQtc(driver, targetQtc: targetQtc) }

    // Ported
    @Published var vbPorted = 50.0
    @Published var fb = 35.0
    @Published var portDiaCm = 10.0
    @Published var portCount = 1
    var portLenCm: Double {
        Ported.portLengthM(tuningHz: fb, boxVolumeM3: vbPorted / 1000,
                           portDiameterM: portDiaCm / 100, ports: portCount) * 100
    }
    var portFits: Bool { portLenCm > 0 }
}
