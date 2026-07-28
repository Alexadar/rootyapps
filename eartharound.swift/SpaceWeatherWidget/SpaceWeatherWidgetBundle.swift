import WidgetKit
import SwiftUI

@main
struct SpaceWeatherWidgetBundle: WidgetBundle {
    var body: some Widget {
        // Home-screen / desktop sizes only, and absent entirely on the watch: it declared accessory
        // families there, so it showed up in the face picker as a third "Earth Around" entry
        // competing with the two kinds below.
        #if !os(watchOS)
        SpaceWeatherWidget()
        #endif
        // Separate kinds so both can sit on one watch face at once — Kp in the corner, flares
        // in the circular slot. They use accessory families, which the iPhone Lock Screen offers
        // too, so they appear there as well.
        #if os(watchOS) || os(iOS)
        KpComplication()
        FlaresComplication()
        #endif
    }
}
