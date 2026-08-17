import WidgetKit
import SwiftUI

/// Home-screen and desktop widgets for iOS and macOS.
///
/// Separate from `EphemerisWidget/`, which is a **watchOS-only** app-extension holding
/// complications. The two cannot be one target: a watch extension builds against a different SDK
/// and supports only the `accessory*` families.
///
/// What they do share is the rule that decided which complications survived — a widget that can
/// render an empty state gets removed. `MoonPhaseWidget` is answerable from the clock alone and can
/// never be empty. `PlanetaryHoursWidget` is gate-1 and CAN be: it needs the observer's place. It
/// earns its slot by wording both of its empty states — "set a place" is fixable by the user, "no
/// sunrise today" is the sky — rather than rendering a blank that reads as broken.
@main
struct EphemerisWidgetIOSBundle: WidgetBundle {
    var body: some Widget {
        MoonPhaseWidget()
        PlanetaryHoursWidget()
    }
}
