import WidgetKit
import SwiftUI

@main
struct EphemerisWidgetBundle: WidgetBundle {
    /// Separate kinds, not one configurable widget, so several can sit on the same face at once.
    /// All informational — nothing for the wearer to configure.
    ///
    /// Moon and Rising Sign were removed rather than shipped broken. The moon's terminator never
    /// rendered correctly on device across five attempts (see git history), and the rising sign
    /// showed its no-place state because the observer had not reached the watch. Both are worth
    /// having; neither is worth shipping while wrong.
    var body: some Widget {
        RetrogradeComplication()
        NextEventComplication()
    }
}
