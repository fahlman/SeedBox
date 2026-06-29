import XCTest
@testable import SeedBox

@MainActor
final class SeedBoxShortcutsTests: XCTestCase {
    func testShortcutRequestsMapToRoutes() {
        XCTAssertEqual(SeedBoxShortcutRequest.showProblems.route, .problems)
        XCTAssertEqual(SeedBoxShortcutRequest.showWarnings.route, .warnings)
        XCTAssertEqual(SeedBoxShortcutRequest.showErrors.route, .errors)
        XCTAssertEqual(SeedBoxShortcutRequest.showActivity.route, .activity)
        XCTAssertEqual(SeedBoxShortcutRequest.showRestoreHistory.route, .restoreHistory)
    }

    func testRouterStoresAndConsumesPendingRoute() {
        let router = SeedBoxShortcutRouter(notificationCenter: NotificationCenter())

        router.request(route: .modSet(id: "favorites"))

        XCTAssertEqual(router.consumePendingRoute(), .modSet(id: "favorites"))
        XCTAssertNil(router.consumePendingRoute())
    }

    func testModSetEntityMapsFromModSet() {
        let entity = ModSetEntity(modSet: ModSet(id: "favorites", name: "Favorites", disabledFolderNames: []))

        XCTAssertEqual(entity.id, "favorites")
        XCTAssertEqual(entity.name, "Favorites")
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
