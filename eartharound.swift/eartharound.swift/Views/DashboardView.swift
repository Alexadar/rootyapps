import SwiftUI
import SpaceWeatherFeed
import GeomagKit
import HpoKit
import FlareKit
import SolarWindKit

/// spaceweather.com-parity dashboard: solar activity, flares, X-ray flux, solar wind,
/// planetary Kp + forecast, aurora, and the NOAA G/R/S scales — every panel sourced.
/// Each panel takes its side accent (Sun/Earth/Link) via `.tint(sw.side(…))`; values
/// use only the restrained severity/side/brand vocabulary so Night mode recolors cleanly.
struct DashboardView: View {
    let snapshot: SpaceWeatherSnapshot
    var showForecast = true
    var status: FeedStatus? = nil
    @Environment(\.sw) private var sw

    var body: some View {
        // Panel IDs are the `SWPanel` registry cases, so anything holding a ScrollViewReader
        // (today: the marketing self-drive) can scroll straight to a named panel.
        PanelStack {
            scalesPanel.id(SWPanel.scales)
            kpPanel.id(SWPanel.kp)
            solarWindPanel.id(SWPanel.wind)
            flarePanel.id(SWPanel.flare)
            auroraPanel.id(SWPanel.aurora)
            solarPanel.id(SWPanel.solar)
        }
    }

    /// Keyed off the level rather than an array position: the old version indexed a literal array,
    /// so reordering it silently relabelled every storm. These are chip captions standing apart
    /// from their noun, so the base form of each adjective is what the catalog carries.
    private func scaleName(_ level: Int) -> String.LocalizationValue {
        switch level {
        case ...0: return "Quiet"
        case 1:    return "Minor"
        case 2:    return "Moderate"
        case 3:    return "Strong"
        case 4:    return "Severe"
        default:   return "Extreme"
        }
    }

    @ViewBuilder private var scalesPanel: some View {
        if let s = snapshot.scales {
            Panel(id: "scales", title: "NOAA Space Weather Scales", source: "NOAA SWPC", observedAt: s.observedAt,
                  feed: .scales, status: status) {
                HStack(spacing: 8) {
                    ScaleChip(label: "G", level: s.g, name: scaleName(s.g))
                    ScaleChip(label: "R", level: s.r, name: scaleName(s.r))
                    ScaleChip(label: "S", level: s.s, name: scaleName(s.s))
                }
                MeaningLine("Geomagnetic (G), Radio blackout (R), Solar radiation (S). 0 means quiet on that axis.")
            }
            .tint(sw.side(.terra))
        }
    }

    @ViewBuilder private var kpPanel: some View {
        if let k = snapshot.kp {
            // Same panel, preciser oracle: the level comes from Hp30 when GFZ has it, so the
            // headline moves with a developing storm instead of waiting on the 3-hourly interval.
            // Everything derived — G-scale, activity wording, ap amplitude — follows that value, or
            // the tiles would describe two different moments side by side. The chart below stays
            // Kp: it is the only series carrying NOAA's forecast.
            let level = snapshot.geomagNow ?? k.now
            let g = snapshot.geomagGScale
            Panel(id: "kp", title: "Geomagnetic Activity", source: snapshot.geomagSource,
                  observedAt: snapshot.geomagObservedAt ?? k.observedAt,
                  feed: snapshot.hpo != nil ? .hpo : .kp, status: status) {
                HStack(spacing: 12) {
                    MetricTile(id: "kp.now", value: Fmt.num(level, 1), caption: "Level now",
                               color: sw.severity(g))
                    MetricTile(id: "kp.gScale", value: g > 0 ? "G\(g)" : "—",
                               caption: SWText.key(Geomag.activity(forKp: level)))
                    MetricTile(id: "kp.ap", value: "\(Geomag.ap(forKp: level))", unit: "ap", caption: "amplitude")
                }
                // 30-minute resolution, matching the headline. The 3-hourly Kp bars drew eight
                // steps a day and flattened exactly the sub-hour rise the readout now reports;
                // NOAA's forecast keeps its own panel on the Geomagnetic tab, which is labelled
                // as a forecast rather than mixed into a measured trace.
                if let h = snapshot.hpo {
                    Hp30Chart(readings: h.readings.filter {
                        $0.time >= Date().addingTimeInterval(-24 * 3600)
                    })
                } else {
                    KpBarChart(series: k.series, showForecast: showForecast)
                }
                MeaningLine(SWText.kpMeaning(kp: Fmt.num(level, 1),
                                             activity: Geomag.activity(forKp: level),
                                             forecast: showForecast))
            }
            .tint(sw.side(.terra))
        }
    }

    @ViewBuilder private var solarWindPanel: some View {
        if let w = snapshot.wind {
            Panel(id: "wind", title: "Solar Wind", source: "NOAA SWPC · DSCOVR/ACE", observedAt: w.observedAt,
                  feed: .wind, status: status) {
                HStack(spacing: 12) {
                    MetricTile(id: "wind.speed", value: Fmt.num(w.speed, 0), unit: "km/s",
                               caption: SWText.key(w.speedDescription, fallback: "speed"), color: sw.side(.link))
                    MetricTile(id: "wind.density", value: Fmt.num(w.density, 1), unit: "p/cm³", caption: "density")
                    MetricTile(id: "wind.bz", value: Fmt.num(w.bz, 1), unit: "nT", caption: "Bz GSM",
                               color: (w.bz ?? 0) < 0 ? sw.warning : nil)
                }
                HStack(spacing: 12) {
                    MetricTile(id: "wind.pressure", value: Fmt.num(w.pressure, 1), unit: "nPa", caption: "dyn. pressure")
                    MetricTile(id: "wind.efield", value: Fmt.num(w.electricField, 1), unit: "mV/m", caption: "E-field (south)")
                    MetricTile(id: "wind.bt", value: Fmt.num(w.bt, 1), unit: "nT", caption: "Bt")
                }
                HStack(spacing: 8) {
                    FlagPill(id: "wind.flag.southward", text: "Southward Bz", on: w.coupling.southward)
                    FlagPill(id: "wind.flag.fastStream", text: "Fast stream", on: w.coupling.fastStream)
                    FlagPill(id: "wind.flag.geoeffective", text: "Geoeffective", on: w.coupling.geoeffective)
                }
                MeaningLine(windMeaning(w))
            }
            .tint(sw.side(.link))
        }
    }

    private func windMeaning(_ w: SolarWindPanel) -> String.LocalizationValue {
        switch w.level {
        case .storming: return "Southward IMF and a fast wind are coupling energy in — storm conditions likely."
        case .elevated: return "Southward IMF is reconnecting with Earth's field; conditions are elevated."
        case .calm: return "The interplanetary field is northward or weak — little coupling to Earth."
        }
    }

    @ViewBuilder private var flarePanel: some View {
        if let f = snapshot.flare {
            Panel(id: "flare", title: "Solar Flares & X-ray Flux", source: "NOAA SWPC · GOES", observedAt: f.observedAt,
                  feed: .flares, status: status) {
                HStack(spacing: 12) {
                    MetricTile(id: "flare.current", value: f.currentClass, caption: "current flux",
                               color: sw.severity(flareClass: f.currentClass))
                    MetricTile(id: "flare.rScale", value: f.rScale > 0 ? "R\(f.rScale)" : "—", caption: SWText.key(Flare.rLabel(f.rScale)))
                    if let ev = f.latestFlare {
                        MetricTile(id: "flare.latest", value: ev.maxClass, caption: "latest flare",
                                   color: sw.severity(flareClass: ev.maxClass))
                    }
                    // Strongest event of the last 24 h. Current flux says what the Sun is doing
                    // this minute; this says what kind of day it has been.
                    if let peak = f.peak24h {
                        MetricTile(id: "flare.peak24h", value: peak.maxClass, caption: "24h peak",
                                   color: sw.severity(flareClass: peak.maxClass))
                    }
                }
                XRayFluxChart(series: f.fluxSeries)
                MeaningLine(SWText.key(f.latestFlare?.meaning ?? Flare.meaning(forClass: f.currentClass)))
            }
            .tint(sw.side(.solar))
        }
    }

    @ViewBuilder private var auroraPanel: some View {
        if let a = snapshot.aurora {
            Panel(id: "aurora", title: "Aurora", source: "NOAA SWPC · OVATION", observedAt: a.observedAt,
                  feed: .aurora, status: status) {
                HStack(spacing: 12) {
                    MetricTile(id: "aurora.probability", value: "\(a.maxProbability)", unit: "%", caption: "peak probability",
                               color: sw.side(.terra))
                    MetricTile(id: "aurora.viewLine", value: Fmt.num(a.viewLineLatitude, 0), unit: "°",
                               caption: "view line (geomag lat)")
                }
                MeaningLine(SWText.auroraViewLine(kp: a.kp))
            }
            .tint(sw.side(.terra))
        }
    }

    @ViewBuilder private var solarPanel: some View {
        if let s = snapshot.solar {
            Panel(id: "solar", title: "Solar Activity", source: "NOAA SWPC · Wolf R", observedAt: s.observedAt,
                  feed: .solar, status: status) {
                HStack(spacing: 12) {
                    MetricTile(id: "solar.sunspots", value: Fmt.int(s.sunspotNumber), caption: SWText.key(s.activity, fallback: "sunspot no."),
                               color: sw.side(.solar))
                    MetricTile(id: "solar.f107", value: Fmt.num(s.f107, 0), unit: "sfu",
                               caption: SWText.f107(s.f107Level))
                    MetricTile(id: "solar.regions", value: Fmt.int(s.regionCount), caption: "active regions")
                }
                MeaningLine("Sunspot number R = 10·groups + spots (Wolf/SILSO), from NOAA's solar-region report.")
            }
            .tint(sw.side(.solar))
        }
    }
}
