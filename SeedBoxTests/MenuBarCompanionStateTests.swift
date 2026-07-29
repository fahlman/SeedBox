import XCTest
@testable import SeedBox

@MainActor
final class MenuBarCompanionStateTests: SeedBoxTestCase {
    func testLoadsPersistedPreference() throws {
        let defaults = try makeIsolatedUserDefaults()
        defaults.set(true, forKey: MenuBarCompanionState.enabledDefaultsKey)

        let state = MenuBarCompanionState(defaults: defaults)

        XCTAssertTrue(state.isEnabled)
    }

    func testPersistsPreferenceChanges() throws {
        let defaults = try makeIsolatedUserDefaults()
        let state = MenuBarCompanionState(defaults: defaults)

        state.isEnabled = true

        XCTAssertTrue(
            defaults.bool(forKey: MenuBarCompanionState.enabledDefaultsKey)
        )
    }
}
