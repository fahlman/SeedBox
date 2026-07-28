import XCTest
@testable import SeedBox

@MainActor
final class HelpViewTests: XCTestCase {
    func testFirstReleaseHelpTopicsArePresent() {
        let topics = HelpView.topics

        XCTAssertEqual(
            topics.map(\.id),
            [
                "getting-started",
                "adding-mods",
                "mod-sets",
                "updates",
                "restore-history",
                "smapi-log",
                "troubleshooting",
                "diagnostics",
                "privacy"
            ]
        )
        XCTAssertEqual(Set(topics.map(\.id)).count, topics.count)
        XCTAssertTrue(topics.allSatisfy { !$0.title.isEmpty })
        XCTAssertTrue(topics.allSatisfy { !$0.body.isEmpty })
        XCTAssertTrue(topics.allSatisfy { !$0.systemImage.isEmpty })
    }

    func testHelpUsesHTTPSIssueURL() throws {
        let url = HelpView.issuesURL

        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "github.com")
        XCTAssertTrue(url.path.contains("SeedBox"))
    }
}
