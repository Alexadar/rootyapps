//
//  LocalizedString.swift
//  eartharound.swift
//
//  Created by Oleksandr Koreniuk on 06.11.2025.
//

import Foundation

enum LocalizedString {
    // General
    static let appTitle = NSLocalizedString("app.title", comment: "")
    static let appSubtitle = NSLocalizedString("app.subtitle", comment: "")

    // Time
    static let today = NSLocalizedString("time.today", comment: "")
    static let yesterday = NSLocalizedString("time.yesterday", comment: "")

    // Event Types
    static let cold = NSLocalizedString("event.cold", comment: "")
    static let heat = NSLocalizedString("event.heat", comment: "")
    static let wind = NSLocalizedString("event.wind", comment: "")
    static let gust = NSLocalizedString("event.gust", comment: "")
    static let rain = NSLocalizedString("event.rain", comment: "")
    static let geomagnetic = NSLocalizedString("event.geomagnetic", comment: "")
    static let solarWind = NSLocalizedString("event.solar_wind", comment: "")
    static let solarFlare = NSLocalizedString("event.solar_flare", comment: "")

    // Event Details
    static let detailTitle = NSLocalizedString("detail.title", comment: "")
    static let detailType = NSLocalizedString("detail.type", comment: "")
    static let detailValue = NSLocalizedString("detail.value", comment: "")
    static let detailCount = NSLocalizedString("detail.count", comment: "")
    static let detailMaxValue = NSLocalizedString("detail.max_value", comment: "")
    static let detailClose = NSLocalizedString("detail.close", comment: "")

    // States
    static let noExtremes = NSLocalizedString("state.no_extremes", comment: "")
    static let loading = NSLocalizedString("state.loading", comment: "")
    static let error = NSLocalizedString("state.error", comment: "")

    static func eventName(for type: ExtremeEventType) -> String {
        switch type {
        case .cold: return cold
        case .heat: return heat
        case .wind: return wind
        case .gust: return gust
        case .rain: return rain
        case .geomagnetic: return geomagnetic
        case .solarWind: return solarWind
        case .solarFlare: return solarFlare
        }
    }
}
