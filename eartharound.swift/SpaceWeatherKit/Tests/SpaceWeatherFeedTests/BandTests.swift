import Testing
import Foundation
import SpaceWeatherFeed
import Foundation
import GeomagKit
import FlareKit
import SolarWindKit
import SolarIndexKit

/// ORACLE = the same published boundaries the English renderings already encode. These bands exist so
/// the app can say the words in the user's language while the Kits keep doing the classifying:
///  • Kp activity: quiet <1, unsettled <3, active <5, storm ≥5 (storm = NOAA G1 onset,
///    "NOAA Space Weather Scales").
///  • Solar-wind speed: slow <350, nominal <500, fast stream <700, very fast above.
///  • Sunspot-number and F10.7 bands per SolarIndexKit's documented thresholds; the quiet-Sun F10.7
///    floor sits near 67 sfu.
///  • Flare severity follows the GOES class letter: X major, M medium, C common, A/B background.
///
/// The invariant under test is that each band agrees with the English function it replaces — so a
/// translated UI can never say something the validated English rendering would not.
@Suite("Classification bands — the localizable half of the Kit prose")
struct BandTests {

    @Test func kpActivityBandsMatchTheEnglishRendering() {
        #expect(Geomag.activityBand(forKp: 0.0) == .quiet)
        #expect(Geomag.activityBand(forKp: 0.99) == .quiet)
        #expect(Geomag.activityBand(forKp: 1.0) == .unsettled)
        #expect(Geomag.activityBand(forKp: 2.9) == .unsettled)
        #expect(Geomag.activityBand(forKp: 3.0) == .active)
        #expect(Geomag.activityBand(forKp: 4.9) == .active)
        #expect(Geomag.activityBand(forKp: 5.0) == .storm)   // G1 begins
        #expect(Geomag.activityBand(forKp: 9.0) == .storm)

        for i in 0...90 {
            let kp = Double(i) / 10.0
            switch Geomag.activityBand(forKp: kp) {
            case .quiet:     #expect(Geomag.activity(forKp: kp) == "Quiet")
            case .unsettled: #expect(Geomag.activity(forKp: kp) == "Unsettled")
            case .active:    #expect(Geomag.activity(forKp: kp) == "Active")
            case .storm:     #expect(Geomag.activity(forKp: kp) == Geomag.gLabel(Geomag.gScale(forKp: kp)))
            }
        }
    }

    @Test func speedBandsMatchTheEnglishRendering() {
        #expect(SolarWind.speedBand(300) == .slow)
        #expect(SolarWind.speedBand(350) == .nominal)
        #expect(SolarWind.speedBand(499) == .nominal)
        #expect(SolarWind.speedBand(500) == .fastStream)
        #expect(SolarWind.speedBand(699) == .fastStream)
        #expect(SolarWind.speedBand(700) == .veryFast)

        for i in stride(from: 200, through: 900, by: 5) {
            let v = Double(i)
            let expected: String
            switch SolarWind.speedBand(v) {
            case .slow:       expected = "Slow"
            case .nominal:    expected = "Nominal"
            case .fastStream: expected = "Fast stream"
            case .veryFast:   expected = "Very fast"
            }
            #expect(SolarWind.speedDescription(v) == expected)
        }
    }

    @Test func sunspotAndF107BandsMatchTheEnglishRendering() {
        #expect(SolarIndex.activityBand(sunspotNumber: 0) == .spotless)
        #expect(SolarIndex.activityBand(sunspotNumber: 200) == .veryHigh)
        #expect(SolarIndex.f107Band(67) == .spotless)        // quiet-Sun floor
        #expect(SolarIndex.f107Band(250) == .veryHigh)

        for i in stride(from: 0, through: 300, by: 5) {
            let r = Double(i)
            let expected: String
            switch SolarIndex.activityBand(sunspotNumber: r) {
            case .spotless: expected = "Spotless"
            case .low:      expected = "Low"
            case .moderate: expected = "Moderate"
            case .high:     expected = "High"
            case .veryHigh: expected = "Very high"
            }
            #expect(SolarIndex.activity(sunspotNumber: r) == expected)
        }
        for i in stride(from: 50, through: 300, by: 5) {
            let sfu = Double(i)
            let expected: String
            switch SolarIndex.f107Band(sfu) {
            case .spotless: expected = "Very low"   // F10.7's floor band reads differently
            case .low:      expected = "Low"
            case .moderate: expected = "Moderate"
            case .high:     expected = "High"
            case .veryHigh: expected = "Very high"
            }
            #expect(SolarIndex.f107Level(sfu) == expected)
        }
    }

    @Test func flareSeverityFollowsTheClassLetter() {
        #expect(Flare.severity(forClass: "X1.0") == .major)
        #expect(Flare.severity(forClass: "M3.2") == .medium)
        #expect(Flare.severity(forClass: "C5.4") == .common)
        #expect(Flare.severity(forClass: "B9.9") == .background)
        #expect(Flare.severity(forClass: "A1.0") == .background)
        #expect(Flare.severity(forClass: "") == .background)

        for cls in ["X1.0", "M3.2", "C5.4", "B9.9", "A1.0", ""] {
            let expected: String
            switch Flare.severity(forClass: cls) {
            case .major:      expected = "Major flare — radio blackouts, possible radiation storm."
            case .medium:     expected = "Medium flare — brief radio blackouts on the sunlit side."
            case .common:     expected = "Common flare — few noticeable effects on Earth."
            case .background: expected = "Minor background activity."
            }
            #expect(Flare.meaning(forClass: cls) == expected)
        }
    }
}

@Suite("Kp 24-hour peak")
struct KpPeakTests {
    private func sample(_ hoursAgo: Double, _ kp: Double, predicted: Bool = false) -> KpSample {
        KpSample(time: Date(timeIntervalSince1970: 1_750_000_000 - hoursAgo * 3600),
                 kp: kp, predicted: predicted)
    }

    @Test("takes the highest observed value inside the window")
    func peakWithinWindow() {
        let p = KpPanel(series: [sample(30, 8.0), sample(20, 5.3), sample(2, 3.0), sample(0, 1.7)],
                        observedAt: nil)
        // 8.0 is 30 h old — outside the 24 h window, so the peak is 5.3.
        #expect(p.peak24h == 5.3)
    }

    @Test("ignores forecast rows")
    func ignoresForecast() {
        let p = KpPanel(series: [sample(1, 2.0), sample(0, 1.7), sample(-6, 7.0, predicted: true)],
                        observedAt: nil)
        // A predicted 7.0 must not be reported as a peak that occurred.
        #expect(p.peak24h == 2.0)
    }

    @Test("nil when nothing has been observed")
    func noObservations() {
        let p = KpPanel(series: [sample(-3, 5.0, predicted: true)], observedAt: nil)
        #expect(p.peak24h == nil)
    }
}
