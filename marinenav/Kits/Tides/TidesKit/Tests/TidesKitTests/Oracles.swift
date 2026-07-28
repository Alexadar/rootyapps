import Foundation

/// External-authority ground truth. See `calculators/VALIDATION.md` and
/// `marinenav/research/SOURCES.md`.
///
/// Expected numbers live **only** here, each tied to a cited external `source`
/// that includes a URI. Reference tests pull values through `Oracles.require(_:)`
/// so a test cannot hardcode a number that has no citation.
struct Oracle {
    let id: String
    let source: String
    let inputs: String
    let precision: String
    let values: [String: Double]
    let tolerances: [String: Double]

    func value(_ key: String) -> Double {
        guard let v = values[key] else { fatalError("oracle \(id) has no value '\(key)'") }
        return v
    }

    func tolerance(_ key: String) -> Double {
        guard let t = tolerances[key] else { fatalError("oracle \(id) has no tolerance '\(key)'") }
        return t
    }

    func matches(_ key: String, _ actual: Double) -> Bool {
        abs(actual - value(key)) <= tolerance(key)
    }
}

enum Oracles {

    static let schuremanSP98 =
        "Schureman, Manual of Harmonic Analysis and Prediction of Tides, USC&GS Special "
        + "Publication No. 98 (1958). U.S. Government work, public domain. "
        + "https://tidesandcurrents.noaa.gov/publications/SpecialPubNo98.pdf"

    static let parkerCOOPS3 =
        "Parker, Tidal Analysis and Prediction, NOAA Special Publication NOS CO-OPS 3 (2007). "
        + "U.S. Government work, public domain. "
        + "https://repository.library.noaa.gov/view/noaa/50576/noaa_50576_DS1.pdf"

    static func noaaStation(_ id: String, _ what: String) -> String {
        "NOAA CO-OPS published \(what) for station \(id), retrieved 2026-07-26. "
        + "U.S. Government work, public domain. https://api.tidesandcurrents.noaa.gov"
    }

    static let all: [Oracle] = [

        // MARK: - Schureman Table 6: nodal angles for each degree of N
        // Header: "Positive when N is between 0 and 180 deg; negative when N is
        // between 180 and 360 deg." Rows transcribed for N = 320..339.
        Oracle(
            id: "schureman-table6-n339",
            source: schuremanSP98 + " -- Table 6, p. 173+ (N = 339 deg)",
            inputs: "N = 339 deg",
            precision: "table printed to 0.01 deg",
            values: ["I": 28.31, "nu": -3.88, "xi": -3.50, "nu_prime": -2.77, "two_nu_dprime": -5.87],
            tolerances: ["I": 0.02, "nu": 0.02, "xi": 0.02, "nu_prime": 0.02, "two_nu_dprime": 0.02]
        ),
        Oracle(
            id: "schureman-table6-n336",
            source: schuremanSP98 + " -- Table 6, p. 173+ (N = 336 deg)",
            inputs: "N = 336 deg",
            precision: "table printed to 0.01 deg",
            values: ["I": 28.23, "nu": -4.42, "xi": -3.98, "nu_prime": -3.15, "two_nu_dprime": -6.68],
            tolerances: ["I": 0.02, "nu": 0.02, "xi": 0.02, "nu_prime": 0.02, "two_nu_dprime": 0.02]
        ),
        Oracle(
            id: "schureman-table6-n330",
            source: schuremanSP98 + " -- Table 6, p. 173+ (N = 330 deg)",
            inputs: "N = 330 deg",
            precision: "table printed to 0.01 deg",
            values: ["I": 28.02, "nu": -5.48, "xi": -4.94, "nu_prime": -3.90, "two_nu_dprime": -8.25],
            tolerances: ["I": 0.02, "nu": 0.02, "xi": 0.02, "nu_prime": 0.02, "two_nu_dprime": 0.02]
        ),
        Oracle(
            id: "schureman-table6-n324",
            source: schuremanSP98 + " -- Table 6, p. 173+ (N = 324 deg)",
            inputs: "N = 324 deg",
            precision: "table printed to 0.01 deg",
            values: ["I": 27.77, "nu": -6.50, "xi": -5.86, "nu_prime": -4.62, "two_nu_dprime": -9.74],
            tolerances: ["I": 0.02, "nu": 0.02, "xi": 0.02, "nu_prime": 0.02, "two_nu_dprime": 0.02]
        ),
        Oracle(
            id: "schureman-table6-n320",
            source: schuremanSP98 + " -- Table 6, p. 173+ (N = 320 deg)",
            inputs: "N = 320 deg",
            precision: "table printed to 0.01 deg",
            values: ["I": 27.58, "nu": -7.15, "xi": -6.46, "nu_prime": -5.08, "two_nu_dprime": -10.69],
            tolerances: ["I": 0.02, "nu": 0.02, "xi": 0.02, "nu_prime": 0.02, "two_nu_dprime": 0.02]
        ),

        // MARK: - NOAA published constituent speeds
        // Our Doodson coefficients must reproduce NOAA's own `speed` field.
        Oracle(
            id: "noaa-constituent-speeds",
            source: noaaStation("9414290", "harmonic constituent speeds (deg/solar hour)")
                + " ; cross-checked against " + schuremanSP98 + " Table 2, pp. 164-166",
            inputs: "all 37 constituent names",
            precision: "NOAA publishes speed to 1e-6 deg/hr",
            values: ["max_abs_error_deg_per_hour": 0.0],
            tolerances: ["max_abs_error_deg_per_hour": 1.0e-5]
        ),

        // MARK: - Parker eq. 3.2, epoch conversion
        Oracle(
            id: "parker-eq32-epoch-9414290",
            source: parkerCOOPS3 + " -- eq. (3.2), p. 93; checked against "
                + noaaStation("9414290", "phase_GMT / phase_local constituent pairs"),
            inputs: "station 9414290, local time meridian S = 120 deg W",
            precision: "NOAA publishes both phases to 0.1 deg",
            values: ["max_abs_error_deg": 0.0],
            tolerances: ["max_abs_error_deg": 0.15]
        ),

        // MARK: - San Francisco 9414290, metres. THE Class-A tide oracle.
        // Our synthesis is driven by NOAA's own published constants and asserted
        // against NOAA's own published predictions. Tolerances are the residuals
        // measured over the embedded window by scratch/tide_full37.py, rounded up.
        Oracle(
            id: "noaa-9414290-hourly-metric",
            source: noaaStation("9414290", "hourly tide predictions, MLLW datum, GMT, metric")
                + " ; synthesised from " + noaaStation("9414290", "37 harmonic constituents + datums"),
            inputs: "2026-03-01T00:00Z .. 2026-03-07T23:00Z, 168 hourly samples",
            precision: "NOAA publishes predictions to 0.001 m",
            values: ["rms_m": 0.0, "max_m": 0.0, "bias_m": 0.0],
            tolerances: ["rms_m": 0.015, "max_m": 0.045, "bias_m": 0.010]
        ),
        Oracle(
            id: "noaa-9414290-z0-metric",
            source: noaaStation("9414290", "datums (epoch 1983-2001), metric"),
            inputs: "MSL and MLLW",
            precision: "NOAA publishes datums to 0.001 m",
            values: ["msl_m": 2.773, "mllw_m": 1.822, "z0_m": 0.951],
            tolerances: ["msl_m": 0.0005, "mllw_m": 0.0005, "z0_m": 0.001]
        ),
        Oracle(
            id: "noaa-9414290-hilo-metric",
            source: noaaStation("9414290", "high/low tide predictions, MLLW datum, GMT, metric"),
            inputs: "2026-03-01 .. 2026-03-07",
            precision: "NOAA publishes times to 1 min and heights to 0.001 m",
            values: ["max_time_error_min": 0.0, "max_height_error_m": 0.0],
            tolerances: ["max_time_error_min": 6.0, "max_height_error_m": 0.045]
        ),

        // MARK: - San Francisco 9414290, FEET.
        // Validated against NOAA's own English-unit output, not a conversion of
        // the metric numbers -- so a unit bug cannot hide in a round-trip.
        Oracle(
            id: "noaa-9414290-hourly-english",
            source: noaaStation("9414290", "hourly tide predictions, MLLW datum, GMT, English (feet)"),
            inputs: "2026-03-01T00:00Z .. 2026-03-07T23:00Z, 168 hourly samples",
            precision: "NOAA publishes predictions to 0.001 ft",
            values: ["rms_ft": 0.0, "max_ft": 0.0],
            tolerances: ["rms_ft": 0.050, "max_ft": 0.150]
        ),

        // MARK: - Galveston Pier 21 8771450, a diurnal regime (contrast station)
        Oracle(
            id: "noaa-8771450-hourly-metric",
            source: noaaStation("8771450", "hourly tide predictions, MLLW datum, GMT, metric")
                + " -- Galveston Pier 21, TX; diurnal regime",
            inputs: "2026-03-01T00:00Z .. 2026-03-07T23:00Z, 168 hourly samples",
            precision: "NOAA publishes predictions to 0.001 m",
            values: ["rms_m": 0.0, "max_m": 0.0],
            tolerances: ["rms_m": 0.008, "max_m": 0.020]
        ),

        // MARK: - Currents: ACT1616 Pollock Rip Channel
        Oracle(
            id: "noaa-ACT1616-currents",
            source: noaaStation("ACT1616", "30-minute current predictions, bin 1, GMT, cm/s")
                + " ; synthesised from " + noaaStation("ACT1616", "bin 1 current harmonic constants"),
            inputs: "2026-03-01T00:00Z .. 2026-03-07, 30-minute samples, major axis",
            precision: "NOAA publishes Velocity_Major to 0.1 cm/s",
            values: ["rms_cms": 0.0, "max_cms": 0.0],
            tolerances: ["rms_cms": 2.5, "max_cms": 7.0]
        ),
        Oracle(
            id: "noaa-ACT1616-events",
            source: noaaStation("ACT1616", "slack / max flood / max ebb current predictions "
                                + "(MAX_SLACK product), bin 1, GMT"),
            inputs: "2026-03-01 .. 2026-03-07, 55 published events",
            precision: "NOAA publishes event times to 1 min and velocities to 0.1 cm/s",
            values: ["max_time_error_min": 0.0, "max_velocity_error_cms": 0.0],
            tolerances: ["max_time_error_min": 8.0, "max_velocity_error_cms": 7.0]
        ),
        Oracle(
            id: "noaa-ACT1616-axes",
            source: noaaStation("ACT1616", "current predictions -- mean flood/ebb directions"),
            inputs: "station ACT1616 bin 1",
            precision: "NOAA publishes directions to 1 deg",
            values: ["mean_flood_dir_deg": 37.0, "mean_ebb_dir_deg": 226.0],
            tolerances: ["mean_flood_dir_deg": 0.5, "mean_ebb_dir_deg": 0.5]
        ),

        // MARK: - Unit definition
        Oracle(
            id: "international-foot",
            source: "International yard and pound agreement (1959): 1 international foot "
                + "= 0.3048 m exactly. NIST Special Publication 811. "
                + "https://www.nist.gov/pml/special-publication-811",
            inputs: "1 foot",
            precision: "exact by definition",
            values: ["meters_per_foot": 0.3048],
            tolerances: ["meters_per_foot": 0.0]
        ),
    ]

    static func require(_ id: String) -> Oracle {
        guard let o = all.first(where: { $0.id == id }) else {
            fatalError("unknown oracle '\(id)'")
        }
        return o
    }
}
