import SwiftUI
import SpaceWeatherFeed
import GeomagKit
import FlareKit
import SolarWindKit

/// spaceweather.com-parity dashboard: solar activity, flares, X-ray flux, solar wind,
/// planetary Kp + forecast, aurora, and the NOAA G/R/S scales — every panel sourced.
/// Each panel takes its side accent (Sun/Earth/Link) via `.tint(sw.side(…))`; values
/// use only the restrained severity/side/brand vocabulary so Night mode recolors cleanly.
struct DashboardView: View {
    let snapshot: SpaceWeatherSnapshot
    var showForecast = true
    @Environment(\.sw) private var sw

    var body: some View {
        // Panel IDs are the `SWPanel` registry cases, so anything holding a ScrollViewReader
        // (today: the marketing self-drive) can scroll straight to a named panel.
        LazyVStack(spacing: 14) {
            scalesPanel.id(SWPanel.scales)
            kpPanel.id(SWPanel.kp)
            solarWindPanel.id(SWPanel.wind)
            flarePanel.id(SWPanel.flare)
            auroraPanel.id(SWPanel.aurora)
            solarPanel.id(SWPanel.solar)
        }
    }

    private func scaleName(_ level: Int) -> String {
        ["Quiet", "Minor", "Moderate", "Strong", "Severe", "Extreme"][min(max(level, 0), 5)]
    }

    @ViewBuilder private var scalesPanel: some View {
        if let s = snapshot.scales {
            Panel(title: "NOAA Space Weather Scales", source: "NOAA SWPC", observedAt: s.observedAt) {
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
            Panel(title: "Planetary Kp", source: "NOAA SWPC", observedAt: k.observedAt) {
                HStack(spacing: 12) {
                    MetricTile(value: Fmt.num(k.now, 1), caption: "Kp now",
                               color: sw.severity(k.gScale))
                    MetricTile(value: k.gScale > 0 ? "G\(k.gScale)" : "—", caption: k.activity)
                    MetricTile(value: "\(k.ap)", unit: "ap", caption: "amplitude")
                }
                KpBarChart(series: k.series, showForecast: showForecast)
                MeaningLine("Kp \(Fmt.num(k.now, 1)) — \(k.activity).\(showForecast ? " Faded bars are the NOAA 3-day forecast." : "")")
            }
            .tint(sw.side(.terra))
        }
    }

    @ViewBuilder private var solarWindPanel: some View {
        if let w = snapshot.wind {
            Panel(title: "Solar Wind", source: "NOAA SWPC · DSCOVR/ACE", observedAt: w.observedAt) {
                HStack(spacing: 12) {
                    MetricTile(value: Fmt.num(w.speed, 0), unit: "km/s",
                               caption: w.speedDescription ?? "speed", color: sw.side(.link))
                    MetricTile(value: Fmt.num(w.density, 1), unit: "p/cm³", caption: "density")
                    MetricTile(value: Fmt.num(w.bz, 1), unit: "nT", caption: "Bz GSM",
                               color: (w.bz ?? 0) < 0 ? sw.warning : nil)
                }
                HStack(spacing: 12) {
                    MetricTile(value: Fmt.num(w.pressure, 1), unit: "nPa", caption: "dyn. pressure")
                    MetricTile(value: Fmt.num(w.electricField, 1), unit: "mV/m", caption: "E-field (south)")
                    MetricTile(value: Fmt.num(w.bt, 1), unit: "nT", caption: "Bt")
                }
                HStack(spacing: 8) {
                    FlagPill(text: "Southward Bz", on: w.coupling.southward)
                    FlagPill(text: "Fast stream", on: w.coupling.fastStream)
                    FlagPill(text: "Geoeffective", on: w.coupling.geoeffective)
                }
                MeaningLine(windMeaning(w))
            }
            .tint(sw.side(.link))
        }
    }

    private func windMeaning(_ w: SolarWindPanel) -> String {
        switch w.level {
        case .storming: return "Southward IMF and a fast wind are coupling energy in — storm conditions likely."
        case .elevated: return "Southward IMF is reconnecting with Earth's field; conditions are elevated."
        case .calm: return "The interplanetary field is northward or weak — little coupling to Earth."
        }
    }

    @ViewBuilder private var flarePanel: some View {
        if let f = snapshot.flare {
            Panel(title: "Solar Flares & X-ray Flux", source: "NOAA SWPC · GOES", observedAt: f.observedAt) {
                HStack(spacing: 12) {
                    MetricTile(value: f.currentClass, caption: "current flux",
                               color: sw.severity(flareClass: f.currentClass))
                    MetricTile(value: f.rScale > 0 ? "R\(f.rScale)" : "—", caption: Flare.rLabel(f.rScale))
                    if let ev = f.latestFlare {
                        MetricTile(value: ev.maxClass, caption: "latest flare",
                                   color: sw.severity(flareClass: ev.maxClass))
                    }
                }
                XRayFluxChart(series: f.fluxSeries)
                MeaningLine(f.latestFlare?.meaning ?? Flare.meaning(forClass: f.currentClass))
            }
            .tint(sw.side(.solar))
        }
    }

    @ViewBuilder private var auroraPanel: some View {
        if let a = snapshot.aurora {
            Panel(title: "Aurora", source: "NOAA SWPC · OVATION", observedAt: a.observedAt) {
                HStack(spacing: 12) {
                    MetricTile(value: "\(a.maxProbability)", unit: "%", caption: "peak probability",
                               color: sw.side(.terra))
                    MetricTile(value: Fmt.num(a.viewLineLatitude, 0), unit: "°",
                               caption: "view line (geomag lat)")
                }
                MeaningLine(a.viewLine)
            }
            .tint(sw.side(.terra))
        }
    }

    @ViewBuilder private var solarPanel: some View {
        if let s = snapshot.solar {
            Panel(title: "Solar Activity", source: "NOAA SWPC · Wolf R", observedAt: s.observedAt) {
                HStack(spacing: 12) {
                    MetricTile(value: Fmt.int(s.sunspotNumber), caption: s.activity ?? "sunspot no.",
                               color: sw.side(.solar))
                    MetricTile(value: Fmt.num(s.f107, 0), unit: "sfu",
                               caption: "F10.7 · \(s.f107Level ?? "")")
                    MetricTile(value: Fmt.int(s.regionCount), caption: "active regions")
                }
                MeaningLine("Sunspot number R = 10·groups + spots (Wolf/SILSO), from NOAA's solar-region report.")
            }
            .tint(sw.side(.solar))
        }
    }
}
