import Foundation
import Observation

/// Every tool's working state, held for the life of the app and written to disk when the app
/// leaves the foreground.
///
/// ## Why this exists
///
/// The design handoff flagged persistence as unwired, and the brief is specific about why it
/// matters: the user is in a crawlspace, half-way through a calculation, and the phone rings. The
/// state has to be there when they come back — not a fresh screen with default values.
///
/// So each tool's model is `Codable`, this container owns all six, and ``saveAll()`` runs on every
/// move out of `.active`. Restoring is per-tool: a model that fails to decode starts fresh instead
/// of taking the whole app down with it.
@Observable
final class AppModels {

    let psychrometrics: PsychrometricsModel
    let heat: HeatModel
    let mixing: MixingModel
    let duct: DuctModel
    let fan: FanModel
    let pipe: PipeModel

    init(psychrometrics: PsychrometricsModel = PsychrometricsModel(),
         heat: HeatModel = HeatModel(),
         mixing: MixingModel = MixingModel(),
         duct: DuctModel = DuctModel(),
         fan: FanModel = FanModel(),
         pipe: PipeModel = PipeModel()) {
        self.psychrometrics = psychrometrics
        self.heat = heat
        self.mixing = mixing
        self.duct = duct
        self.fan = fan
        self.pipe = pipe
    }

    static func loaded() -> AppModels {
        AppModels(psychrometrics: .loaded(), heat: .loaded(), mixing: .loaded(),
                  duct: .loaded(), fan: .loaded(), pipe: .loaded())
    }

    func saveAll() {
        psychrometrics.save()
        heat.save()
        mixing.save()
        duct.save()
        fan.save()
        pipe.save()
    }
}
