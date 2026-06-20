import XCTest
@testable import SeedBox

final class AppDistributionChannelTests: XCTestCase {
    func testCurrentChannelMatchesBuildCondition() {
        #if SEEDBOX_STEAM
        XCTAssertEqual(AppDistributionChannel.current, .steam)
        #else
        XCTAssertEqual(AppDistributionChannel.current, .appStoreCandidate)
        #endif
    }

    func testAppStoreCandidateChannelUsesSandboxedReleaseTraits() {
        let channel = AppDistributionChannel.appStoreCandidate

        XCTAssertTrue(channel.usesAppSandbox)
        XCTAssertFalse(channel.supportsSteamworksIntegration)
        XCTAssertEqual(channel.releaseConfigurationName, "Release")
        XCTAssertEqual(channel.entitlementsPath, "SeedBox/Sandbox.entitlements")
    }

    func testSteamChannelUsesDeveloperIDReleaseTraits() {
        let channel = AppDistributionChannel.steam

        XCTAssertFalse(channel.usesAppSandbox)
        XCTAssertTrue(channel.supportsSteamworksIntegration)
        XCTAssertEqual(channel.releaseConfigurationName, "Release Steam")
        XCTAssertEqual(channel.entitlementsPath, "SeedBox/Steam.entitlements")
    }
}
