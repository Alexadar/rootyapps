import WidgetKit
import SwiftUI

@main
struct EphemerisWidgetBundle: WidgetBundle {
    /// Four separate kinds, not one configurable widget: each can then sit on the same face at
    /// once — rising sign in the corner, retrograde in a circular slot — and they stay
    /// informational, with nothing for the wearer to configure.
    var body: some Widget {
        RisingSignComplication()
        RetrogradeComplication()
        MoonComplication()
        NextEventComplication()
    }
}

struct RisingSignComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RisingSign", provider: RisingSignProvider()) { entry in
            RisingSignView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Rising Sign")
        .description("The Ascendant for your saved place — it changes about every two hours.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner,
                            .accessoryRectangular, .accessoryInline])
    }
}
