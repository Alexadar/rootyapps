import SwiftUI
import Combine
import SpaceWeatherFeed

/// Persisted theme choice (Dark / Night). Bind to the toolbar toggle in the root header.
/// Read at the root: `.swTheme(theme.selected)`.
/// Lives in the app group so widgets and the watch follow the phone's choice.
@MainActor
final class ThemeStore: ObservableObject {
    @AppStorage(SharedStore.Key.theme, store: AppGroup.defaults)
    private var raw: String = SWThemeChoice.dark.rawValue

    var selected: SWThemeChoice {
        get { SWThemeChoice(rawValue: raw) ?? .dark }
        set { objectWillChange.send(); raw = newValue.rawValue }
    }

    init() {
        // One-shot migration from the pre-app-group location.
        if AppGroup.defaults.string(forKey: SharedStore.Key.theme) == nil,
           let old = UserDefaults.standard.string(forKey: SharedStore.Key.theme) {
            raw = old
        }
    }

    func toggle() { selected = (selected == .dark) ? .night : .dark }
}

/// Theme access for non-observing contexts (widget timeline render, watch first paint).
extension SWThemeChoice {
    static var shared: SWThemeChoice {
        SharedStore().themeRaw.flatMap(SWThemeChoice.init(rawValue:)) ?? .dark
    }
}
