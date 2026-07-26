import Foundation
import GeomagKit
import FlareKit
import HpoKit

/// User's alert preferences. Master switch off by default — alerts are opt-in.
public struct AlertPrefs: Equatable {
    public var enabled: Bool
    public var storms: Bool
    public var stormThreshold: Int    // minimum NOAA G level to notify, 1…5
    public var flares: Bool           // fires at M-class and up (NOAA R1+)
    public var aurora: Bool
    public var auroraThreshold: Int   // minimum OVATION max probability, %

    public init(enabled: Bool = false, storms: Bool = true, stormThreshold: Int = 1,
                flares: Bool = true, aurora: Bool = true, auroraThreshold: Int = 50) {
        self.enabled = enabled
        self.storms = storms
        self.stormThreshold = stormThreshold
        self.flares = flares
        self.aurora = aurora
        self.auroraThreshold = auroraThreshold
    }
}

/// What we already notified about, so repeated background runs stay silent until
/// something actually changes. Persisted in the app group.
public struct AlertDedupeState: Equatable, Codable {
    /// Highest G level notified in the current storm episode; 0 re-arms when calm.
    public var lastStormG: Int = 0
    /// max_time of the last flare notified (NOAA's event identity).
    public var lastFlareMaxTime: Date?
    /// UT day of the last aurora notification — at most one per day.
    public var lastAuroraUTDay: Date?
    public init() {}
}

public struct SpaceAlert: Equatable {
    public enum Kind: String { case storm, flare, aurora }
    public let kind: Kind
    public let title: String
    public let body: String
}

/// Pure alert engine. Thresholds are the published NOAA scale boundaries, applied
/// through the Kits — same rule as everywhere else: notify nothing the Kits can't
/// validate, and never re-notify an unchanged condition.
public enum SpaceAlerts {

    public static func evaluate(current: SpaceWeatherSnapshot,
                                prefs: AlertPrefs,
                                state: AlertDedupeState,
                                now: Date = Date()) -> (alerts: [SpaceAlert], state: AlertDedupeState) {
        guard prefs.enabled else { return ([], state) }
        var alerts: [SpaceAlert] = []
        var state = state

        // Geomagnetic storm — fires on onset and on every escalation above the last
        // level we saw. Tracking the *observed* level (not the highest ever notified)
        // means a storm that decays and re-intensifies alerts on its second peak too,
        // while a steady or fading storm stays quiet.
        if prefs.storms {
            if let g = current.scales?.g {
                if g >= prefs.stormThreshold, g > state.lastStormG {
                    let kp = current.kp.map { String(format: " — Kp %.1f", $0.now) } ?? ""
                    alerts.append(SpaceAlert(kind: .storm,
                                             title: "\(Geomag.gLabel(g)) geomagnetic storm",
                                             body: "NOAA G\(g) conditions now\(kp)."))
                }
                state.lastStormG = g
            }
        } else {
            state.lastStormG = 0    // re-arm, so switching storms back on can alert immediately
        }

        // Solar flare — a new M/X event, identified by NOAA's max_time.
        if prefs.flares, let flare = current.flare?.latestFlare,
           flare.rScale >= 1, let maxTime = flare.maxTime, maxTime != state.lastFlareMaxTime {
            alerts.append(SpaceAlert(kind: .flare,
                                     title: "\(flare.maxClass) solar flare",
                                     body: flare.meaning))
            state.lastFlareMaxTime = maxTime
        }

        // Aurora chance — at most one heads-up per UT day.
        if prefs.aurora, let aurora = current.aurora, aurora.maxProbability >= prefs.auroraThreshold {
            let day = Hpo.utDayStart(for: now)
            if day != state.lastAuroraUTDay {
                alerts.append(SpaceAlert(kind: .aurora,
                                         title: "Aurora chance \(aurora.maxProbability)%",
                                         body: aurora.viewLine))
                state.lastAuroraUTDay = day
            }
        }

        return (alerts, state)
    }
}
