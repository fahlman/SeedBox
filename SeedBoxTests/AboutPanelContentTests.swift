import AppKit
import XCTest
@testable import SeedBox

final class AboutPanelContentTests: XCTestCase {
    func testVersionTextIncludesVersionAndBuild() {
        XCTAssertEqual(
            AboutPanelContent.versionText(appVersion: "1.2.3", buildVersion: "45"),
            "Version 1.2.3 (Build 45)"
        )
    }

    func testVersionTextFallsBackWhenBundleValuesAreMissing() {
        XCTAssertEqual(
            AboutPanelContent.versionText(appVersion: nil, buildVersion: nil),
            "Version Unknown Version (Build Unknown Build)"
        )
    }

    func testAboutPanelOptionsUseSeedBoxNameAndVersion() {
        let options = AboutPanelContent.options()

        XCTAssertEqual(options[.applicationName] as? String, AppStrings.App.name)
        XCTAssertNotNil(options[.applicationVersion] as? String)
    }
}
