//
//  EventDetailPreviews.swift
//  eartharound.swift
//
//  Created by Oleksandr Koreniuk on 06.11.2025.
//

import SwiftUI

#if DEBUG
#Preview("Event Detail - Cold") {
    let event = AggregatedEvent(
        type: .cold,
        count: 5,
        maxValue: -22.1,
        stringValue: nil
    )

    EventDetailView(event: event) {
        print("Dismissed")
    }
}

#Preview("Event Detail - Heat") {
    let event = AggregatedEvent(
        type: .heat,
        count: 3,
        maxValue: 41.3,
        stringValue: nil
    )

    EventDetailView(event: event) {
        print("Dismissed")
    }
}

#Preview("Event Detail - Storm") {
    let event = AggregatedEvent(
        type: .gust,
        count: 4,
        maxValue: 95.3,
        stringValue: nil
    )

    EventDetailView(event: event) {
        print("Dismissed")
    }
}

#Preview("Event Detail - Solar Flare") {
    let event = AggregatedEvent(
        type: .solarFlare,
        count: 1,
        maxValue: 0,
        stringValue: "X2.1"
    )

    EventDetailView(event: event) {
        print("Dismissed")
    }
}

#Preview("Event Detail - Geomagnetic") {
    let event = AggregatedEvent(
        type: .geomagnetic,
        count: 2,
        maxValue: 7.5,
        stringValue: nil
    )

    EventDetailView(event: event) {
        print("Dismissed")
    }
}

#Preview("Interactive Panel with Tap") {
    let today = DailyExtremes(date: Date(), events: [
        .wind(65.2), .wind(72.8),
        .gust(85.5), .gust(92.1), .gust(88.7),
        .rain(12.5)
    ])

    ExtremesPanel(title: "Today", extremes: today)
        .padding()
        .frame(maxWidth: 600)
}

#Preview("Full Context - Tappable Events") {
    let today = DailyExtremes(date: Date(), events: [
        .cold(-15.3), .cold(-18.7), .cold(-22.1),
        .wind(65.2),
        .geomagnetic(6.5)
    ])
    let yesterday = DailyExtremes(date: Date().addingTimeInterval(-86400), events: [
        .heat(37.2), .heat(39.8),
        .solarFlare("X2.1")
    ])

    ScrollView {
        VStack(spacing: 16) {
            ExtremesPanel(title: "Today", extremes: today)
            ExtremesPanel(title: "Yesterday", extremes: yesterday)
        }
        .padding()
    }
    .frame(maxWidth: 800)
}
#endif
