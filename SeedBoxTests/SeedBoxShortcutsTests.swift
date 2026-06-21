import XCTest
@testable import SeedBox

@MainActor
final class SeedBoxShortcutsTests: XCTestCase {
    func testShortcutRequestsMapToSheets() {
        XCTAssertEqual(SeedBoxShortcutRequest.showProblems.sheet.id, ModManagerSheet.problems.id)
        XCTAssertEqual(SeedBoxShortcutRequest.showActivity.sheet.id, ModManagerSheet.activity.id)
        XCTAssertEqual(SeedBoxShortcutRequest.showRestoreHistory.sheet.id, ModManagerSheet.restoreHistory.id)
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
