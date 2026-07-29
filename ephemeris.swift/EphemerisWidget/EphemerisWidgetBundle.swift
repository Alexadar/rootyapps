import WidgetKit
import SwiftUI

@main
struct EphemerisWidgetBundle: WidgetBundle {
    var body: some Widget {
        // accessory families, so this appears on the watch face AND the iPhone Lock Screen.
        RisingSignComplication()
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
