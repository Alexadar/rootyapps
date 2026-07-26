import SwiftUI
import Combine
import SpaceWeatherFeed

/// How much detail the UI shows. Simple answers the two questions a general user has —
/// is a storm hitting, will I see aurora — in the Kits' own words; Extended is the full
/// instrument HUD. Lives in the app group (like `sw.theme`) so the widget mirrors it.
enum SWMode: String, CaseIterable, Identifiable {
    case simple, extended
    var id: String { rawValue }
    var label: String { self == .simple ? "Simple" : "Extended" }
}

@MainActor
final class ModeStore: ObservableObject {
    @AppStorage(SharedStore.Key.mode, store: AppGroup.defaults)
    private var raw: String = SWMode.simple.rawValue

    var selected: SWMode {
        get { SWMode(rawValue: raw) ?? .simple }
        set { objectWillChange.send(); raw = newValue.rawValue }
    }

    func toggle() { selected = (selected == .simple) ? .extended : .simple }
}

/// Mode access for non-observing contexts (widget timeline render).
extension SWMode {
    static var shared: SWMode {
        SharedStore().modeRaw.flatMap(SWMode.init(rawValue:)) ?? .simple
    }
}
