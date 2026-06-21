import XCTest
@testable import SeedBox

@MainActor
final class SeedBoxShortcutsTests: XCTestCase {
    func testShortcutRequestsMapToRoutes() {
        XCTAssertEqual(SeedBoxShortcutRequest.showProblems.route, .problems)
        XCTAssertEqual(SeedBoxShortcutRequest.showActivity.route, .activity)
        XCTAssertEqual(SeedBoxShortcutRequest.showRestoreHistory.route, .restoreHistory)
    }

    func testShortcutRouterStoresAndConsumesPendingRequest() {
        let router = SeedBoxShortcutRouter(notificationCenter: NotificationCenter())

        router.request(.showProblems)

        XCTAssertEqual(router.consumePendingRequest(), .showProblems)
        XCTAssertNil(router.consumePendingRequest())
    }

    func testShortcutRouterKeepsLatestPendingRequest() {
        let router = SeedBoxShortcutRouter(notificationCenter: NotificationCenter())

        router.request(.showProblems)
        router.request(.showRestoreHistory)

        XCTAssertEqual(router.consumePendingRequest(), .showRestoreHistory)
    }
}
