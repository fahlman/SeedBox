import Foundation
import Observation

/// Owns the menu bar companion preference for every scene in the app.
///
/// Keeping this as app state avoids separate `@AppStorage` wrappers competing
/// to drive the `MenuBarExtra` scene while still persisting the user's choice.
@MainActor
@Observable
final class MenuBarCompanionState {
    static let enabledDefaultsKey = "seedbox.menuBarCompanionEnabled"

    private let defaults: UserDefaults

    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else {
                return
            }
            defaults.set(isEnabled, forKey: Self.enabledDefaultsKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.enabledDefaultsKey)
    }
}
