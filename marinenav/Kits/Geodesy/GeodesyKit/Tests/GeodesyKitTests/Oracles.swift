import Foundation

/// Oracle corpus — expected numbers exist ONLY here, each tied to a cited external source.
/// Vincenty entries: the classic Flinders↔Buninyong line plus rows transcribed verbatim from
/// Karney's GeodTest-short.dat (previously validated in bulk — 10,000 rows, sub-mm — in
/// calculators/marine-navigation/geodesic.swift; the fixture was gitignored, so a cited subset
/// is embedded here to keep `swift test` green offline).
/// Scoped claim: rows are chosen away from the near-antipodal regime, where Vincenty's inverse
/// is documented not to converge (the Kit reports `converged: false` there, honestly).
struct Oracle {
    let id, source, inputs, precision: String
    let values: [String: Double]; let tolerances: [String: Double]
    func matches(_ k: String, _ a: Double) -> Bool {
        guard let v = values[k], let t = tolerances[k] else { return false }
        return abs(a - v) <= t
    }
}

/// One transcribed GeodTest row (lat1 lon1 azi1 lat2 lon2 azi2 s12 …), lon1 = 0 by construction.
struct GeodTestRow {
    let id: String
    let lat1, lat2, lon2: Double     // inputs
    let s12, azi1, azi2: Double      // expected
}

enum Oracles {
    static let geodTestSource =
        "Karney, GeodTest geodesic test set (GeographicLib, MIT/X11-licensed data), computed by "
      + "multiprecision arithmetic; rows transcribed verbatim from GeodTest-short.dat"

    static let geodTestRows: [GeodTestRow] = [
        GeodTestRow(id: "geodtest-mid-9398km",
                    lat1: 36.530042355041, lat2: -48.164270779097768864, lon2: 5.762344694676510456,
                    s12: 9398502.0434687, azi1: 176.125875162171, azi2: 175.334308316285410561),
        GeodTestRow(id: "geodtest-highlat-5564km",
                    lat1: 50.936172211442, lat2: 78.966384891263396303, lon2: 167.357398986746628656,
                    s12: 5564793.9939781, azi1: 3.142915292264, azi2: 169.612024652716712263),
        GeodTestRow(id: "geodtest-mid-8125km",
                    lat1: 28.149226945471, lat2: 32.014281405870639763, lon2: 86.678685905047216772,
                    s12: 8125880.1298703, azi1: 62.304093156403, azi2: 112.993708428330211417),
        GeodTestRow(id: "geodtest-short-269m",
                    lat1: 24.18940122271, lat2: 24.188424127455853607, lon2: 0.002422166947283588,
                    s12: 268.843807, azi1: 113.737408507569, azi2: 113.738400982050319733),
        GeodTestRow(id: "geodtest-nearpolar-10916km",
                    lat1: 89.99594074843, lat2: -8.271046664189565809, lon2: 120.909368158984602521,
                    s12: 10916827.1568597, azi1: 59.091118115157, azi2: 179.996469020471999782),
        GeodTestRow(id: "geodtest-nearmeridional-4687km",
                    lat1: 10.217226673886, lat2: 52.486660704686269718, lon2: 0.002759046582320927,
                    s12: 4687613.3043724, azi1: 0.002511550442, azi2: 0.004050887056382569),
        GeodTestRow(id: "geodtest-nearequatorial-11557km",
                    lat1: 0.002300507054, lat2: -0.003107210036505316, lon2: 103.824636502814443721,
                    s12: 11557705.6778402, azi1: 90.002614972759, azi2: 90.001582676445389967),
    ]

    static let all: [Oracle] = [
        Oracle(id: "vincenty_flinders_buninyong",
               source: "Vincenty 1975 (Survey Review XXIII/176) worked test line (from Rainsford), "
                     + "Flinders Peak → Buninyong: s = 54 972.271 m, α1 = 306°52′05.37″; published "
                     + "α2 = 127°10′25.07″ is the BACK azimuth — the Kit returns the forward azimuth "
                     + "at point 2, so expected azi2 = 127.17363° + 180° = 307.17363°",
               inputs: "lat1 -37°57′03.72030″, lon1 144°25′29.52440″, lat2 -37°39′10.15610″, lon2 143°55′35.38390″",
               precision: "±0.001 m / ±1e-3°",
               values: ["distance_m": 54972.271, "azi1_deg": 306.86816, "azi2_deg": 307.17363],
               tolerances: ["distance_m": 0.001, "azi1_deg": 1e-3, "azi2_deg": 1e-3]),
    ] + geodTestRows.map { r in
        Oracle(id: r.id, source: geodTestSource,
               inputs: "lat1 \(r.lat1), lon1 0, lat2 \(r.lat2), lon2 \(r.lon2)",
               precision: "±0.001 m / ±1e-3°",
               values: ["distance_m": r.s12, "azi1_deg": r.azi1, "azi2_deg": r.azi2],
               tolerances: ["distance_m": 0.001, "azi1_deg": 1e-3, "azi2_deg": 1e-3])
    }

    static func require(_ id: String) -> Oracle {
        guard let o = all.first(where: { $0.id == id }) else { fatalError("unknown oracle '\(id)'") }
        return o
    }
}
