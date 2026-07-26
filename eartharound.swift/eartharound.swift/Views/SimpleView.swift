import SwiftUI
import SpaceWeatherFeed
import GeomagKit
import FlareKit

/// The general-audience face: three panels answering the only questions most people ask —
/// is a storm hitting, will I see aurora tonight, what did the Sun just do. Every sentence
/// is a Kit string, so Simple states nothing Extended can't back up; the source citations
/// and stale badges stay, because trust is not an expert feature.
struct SimpleView: View {
    let snapshot: SpaceWeatherSnapshot
    @Environment(\.sw) private var sw

    var body: some View {
        // Same `SWPanel` registry ids as Extended, so a ScrollViewReader can still scroll here.
        LazyVStack(spacing: 14) {
            stormPanel.id(SWPanel.scales)
            auroraPanel.id(SWPanel.aurora)
            sunPanel.id(SWPanel.flare)
            if !hasAny { noConditions }
        }
    }

    private var hasAny: Bool {
        snapshot.kp != nil || snapshot.scales != nil || snapshot.aurora != nil || snapshot.flare != nil
    }

    // MARK: - Is a storm hitting?

    @ViewBuilder private var stormPanel: some View {
        if snapshot.kp != nil || snapshot.scales != nil {
            let kp = snapshot.kp
            // NOAA's published G level when we have it; otherwise the Kit derives it from Kp.
            let g = snapshot.scales?.g ?? kp.map { Geomag.gScale(forKp: $0.now) } ?? 0
            Panel(title: "Storm Right Now", source: "NOAA SWPC",
                  observedAt: kp?.observedAt ?? snapshot.scales?.observedAt) {
                HStack(spacing: 12) {
                    MetricTile(value: g > 0 ? "G\(g)" : "None", caption: "storm level",
                               color: sw.severity(g))
                    if let k = kp {
                        MetricTile(value: Fmt.num(k.now, 1), caption: k.activity)
                    }
                }
                if let k = kp {
                    KpBarChart(series: k.series, showForecast: true)
                }
                MeaningLine(stormMeaning(g: g, kp: kp))
            }
            .tint(sw.side(.terra))
        }
    }

    private func stormMeaning(g: Int, kp: KpPanel?) -> String {
        let forecast = kp == nil ? "" : " Faded bars are NOAA's 3-day forecast."
        guard g > 0 else {
            // NOAA's G0 backs "no storm", but quiet-vs-unsettled is a Kp call — with no Kp
            // we stop at what the data supports rather than adding a comfortable adjective.
            guard let k = kp else { return "No geomagnetic storm right now." }
            return "No geomagnetic storm right now — conditions are \(Geomag.activity(forKp: k.now).lowercased()).\(forecast)"
        }
        return "\(Geomag.gLabel(g)) geomagnetic storm in progress.\(forecast)"
    }

    // MARK: - Will I see aurora?

    @ViewBuilder private var auroraPanel: some View {
        if let a = snapshot.aurora {
            Panel(title: "Aurora Tonight", source: "NOAA SWPC · OVATION", observedAt: a.observedAt) {
                MetricTile(value: "\(a.maxProbability)", unit: "%", caption: "best chance now",
                           color: sw.side(.terra))
                // The view line is computed from Kp; with no Kp it silently reads as Kp 0 and
                // would state a confident, wrong latitude. Say nothing rather than that.
                if snapshot.kp != nil {
                    MeaningLine(a.viewLine)
                }
            }
            .tint(sw.side(.terra))
        }
    }

    // MARK: - What did the Sun do?

    @ViewBuilder private var sunPanel: some View {
        if let f = snapshot.flare {
            let r = snapshot.scales?.r ?? 0
            let s = snapshot.scales?.s ?? 0
            Panel(title: "The Sun Today", source: "NOAA SWPC · GOES", observedAt: f.observedAt) {
                MetricTile(value: f.latestFlare?.maxClass ?? f.currentClass, caption: "latest flare",
                           color: sw.severity(flareClass: f.latestFlare?.maxClass ?? f.currentClass))
                MeaningLine(f.latestFlare?.meaning ?? Flare.meaning(forClass: f.currentClass))
                // Radio blackouts and radiation storms ride on the same solar event but are
                // scored separately — without this line an S-storm would read as "all quiet".
                if r > 0 || s > 0 {
                    MeaningLine("Radio blackouts: \(Flare.rLabel(r)). Radiation storm: \(Flare.sLabel(s)).")
                }
            }
            .tint(sw.side(.solar))
        }
    }

    // MARK: - Nothing to show

    private var noConditions: some View {
        Panel(title: "No Current Conditions", source: "NOAA SWPC") {
            MeaningLine("No live storm, aurora or flare data right now. Pull to refresh — nothing is shown until it's real.")
        }
        .tint(sw.side(.terra))
    }
}
