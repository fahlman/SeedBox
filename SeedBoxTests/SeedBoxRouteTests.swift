import XCTest
@testable import SeedBox

final class SeedBoxRouteTests: XCTestCase {
    private let visibleMod = ModInfo(
        id: "visible-mod",
        folderName: "VisibleMod",
        url: URL(fileURLWithPath: "/tmp/SeedBoxTests/Mods/VisibleMod"),
        isEnabled: true,
        manifest: nil
    )
    private let hiddenFromWarningsMod = ModInfo(
        id: "hidden-mod",
        folderName: "HiddenMod",
        url: URL(fileURLWithPath: "/tmp/SeedBoxTests/Mods/HiddenMod"),
        isEnabled: true,
        manifest: nil
    )

    func testDispatchesSheetRoutes() {
        for (route, expectedSheet) in [
            (SeedBoxRoute.problems, ModManagerSheet.problems),
            (.activity, .activity),
            (.restoreHistory, .restoreHistory)
        ] {
            var presentation = ModManagerViewPresentation()
            var selectedLibraryItemID = ModLibrarySelection.defaultID
            var selectedModIDs: Set<String> = ["selected-mod"]

            let result = makeDispatcher().dispatch(
                route,
                presentation: &presentation,
                selectedLibraryItemID: &selectedLibraryItemID,
                selectedModIDs: &selectedModIDs
            )

            XCTAssertEqual(result, .handled)
            XCTAssertEqual(presentation.sheet?.id, expectedSheet.id)
            XCTAssertEqual(selectedLibraryItemID, ModLibrarySelection.defaultID)
            XCTAssertEqual(selectedModIDs, ["selected-mod"])
        }
    }

    func testDispatchesLibraryRoute() {
        var presentation = ModManagerViewPresentation(sheet: .activity)
        var selectedLibraryItemID = "missing-mod-set-id"
        var selectedModIDs: Set<String> = ["selected-mod"]

        let result = makeDispatcher().dispatch(
            .library,
            presentation: &presentation,
            selectedLibraryItemID: &selectedLibraryItemID,
            selectedModIDs: &selectedModIDs
        )

        XCTAssertEqual(result, .handled)
        XCTAssertNil(presentation.sheet)
        XCTAssertEqual(selectedLibraryItemID, ModLibrarySelection.defaultID)
        XCTAssertTrue(selectedModIDs.isEmpty)
    }

    func testDispatchesProblemFilterRoutesToSmartModSets() {
        assertSmartRoute(.warnings, selects: .warnings)
        assertSmartRoute(.errors, selects: .errors)
    }

    func testDispatchesSmartModSetRoute() {
        assertSmartRoute(.smartModSet(.updatesAvailable), selects: .updatesAvailable)
    }

    func testDispatchesUserSmartModSetRoute() {
        var presentation = ModManagerViewPresentation(sheet: .activity)
        var selectedLibraryItemID = ModLibrarySelection.defaultID
        var selectedModIDs: Set<String> = ["selected-mod"]

        let result = makeDispatcher().dispatch(
            .userSmartModSet(id: "visible"),
            presentation: &presentation,
            selectedLibraryItemID: &selectedLibraryItemID,
            selectedModIDs: &selectedModIDs
        )

        XCTAssertEqual(result, .handled)
        XCTAssertNil(presentation.sheet)
        XCTAssertEqual(selectedLibraryItemID, ModLibrarySelection.userSmartID("visible"))
        XCTAssertTrue(selectedModIDs.isEmpty)
    }

    func testMissingUserSmartModSetRouteIsUnavailable() {
        var presentation = ModManagerViewPresentation(sheet: .activity)
        var selectedLibraryItemID = ModLibrarySelection.defaultID
        var selectedModIDs: Set<String> = ["selected-mod"]

        let result = makeDispatcher().dispatch(
            .userSmartModSet(id: "missing"),
            presentation: &presentation,
            selectedLibraryItemID: &selectedLibraryItemID,
            selectedModIDs: &selectedModIDs
        )

        XCTAssertEqual(result, .unavailable)
        XCTAssertEqual(presentation.sheet?.id, ModManagerSheet.activity.id)
        XCTAssertEqual(selectedLibraryItemID, ModLibrarySelection.defaultID)
        XCTAssertEqual(selectedModIDs, ["selected-mod"])
    }

    func testDispatchesModSetRoute() {
        var presentation = ModManagerViewPresentation(sheet: .activity)
        var selectedLibraryItemID = ModLibrarySelection.defaultID
        var selectedModIDs: Set<String> = ["selected-mod"]

        let result = makeDispatcher().dispatch(
            .modSet(id: "favorites"),
            presentation: &presentation,
            selectedLibraryItemID: &selectedLibraryItemID,
            selectedModIDs: &selectedModIDs
        )

        XCTAssertEqual(result, .handled)
        XCTAssertNil(presentation.sheet)
        XCTAssertEqual(selectedLibraryItemID, ModLibrarySelection.modSetID("favorites"))
        XCTAssertTrue(selectedModIDs.isEmpty)
    }

    func testMissingModSetRouteIsUnavailable() {
        var presentation = ModManagerViewPresentation(sheet: .activity)
        var selectedLibraryItemID = ModLibrarySelection.defaultID
        var selectedModIDs: Set<String> = ["selected-mod"]

        let result = makeDispatcher().dispatch(
            .modSet(id: "missing"),
            presentation: &presentation,
            selectedLibraryItemID: &selectedLibraryItemID,
            selectedModIDs: &selectedModIDs
        )

        XCTAssertEqual(result, .unavailable)
        XCTAssertEqual(presentation.sheet?.id, ModManagerSheet.activity.id)
        XCTAssertEqual(selectedLibraryItemID, ModLibrarySelection.defaultID)
        XCTAssertEqual(selectedModIDs, ["selected-mod"])
    }

    func testDispatchesModRouteWithoutChangingCompatibleLibrarySelection() {
        var presentation = ModManagerViewPresentation(sheet: .activity)
        var selectedLibraryItemID = ModLibrarySelection.smartID(.allMods)
        var selectedModIDs: Set<String> = []

        let result = makeDispatcher().dispatch(
            .mod(id: visibleMod.id),
            presentation: &presentation,
            selectedLibraryItemID: &selectedLibraryItemID,
            selectedModIDs: &selectedModIDs
        )

        XCTAssertEqual(result, .handled)
        XCTAssertNil(presentation.sheet)
        XCTAssertEqual(selectedLibraryItemID, ModLibrarySelection.smartID(.allMods))
        XCTAssertEqual(selectedModIDs, [visibleMod.id])
    }

    func testDispatchesModRouteByFallingBackToAllModsWhenCurrentFilterExcludesIt() {
        var presentation = ModManagerViewPresentation(sheet: .activity)
        var selectedLibraryItemID = ModLibrarySelection.smartID(.warnings)
        var selectedModIDs: Set<String> = []

        let result = makeDispatcher().dispatch(
            .mod(id: hiddenFromWarningsMod.id),
            presentation: &presentation,
            selectedLibraryItemID: &selectedLibraryItemID,
            selectedModIDs: &selectedModIDs
        )

        XCTAssertEqual(result, .handled)
        XCTAssertNil(presentation.sheet)
        XCTAssertEqual(selectedLibraryItemID, ModLibrarySelection.smartID(.allMods))
        XCTAssertEqual(selectedModIDs, [hiddenFromWarningsMod.id])
    }

    func testMissingModRouteIsUnavailable() {
        var presentation = ModManagerViewPresentation(sheet: .activity)
        var selectedLibraryItemID = ModLibrarySelection.smartID(.allMods)
        var selectedModIDs: Set<String> = []

        let result = makeDispatcher().dispatch(
            .mod(id: "missing-mod"),
            presentation: &presentation,
            selectedLibraryItemID: &selectedLibraryItemID,
            selectedModIDs: &selectedModIDs
        )

        XCTAssertEqual(result, .unavailable)
        XCTAssertEqual(presentation.sheet?.id, ModManagerSheet.activity.id)
        XCTAssertEqual(selectedLibraryItemID, ModLibrarySelection.smartID(.allMods))
        XCTAssertTrue(selectedModIDs.isEmpty)
    }

    private func assertSmartRoute(
        _ route: SeedBoxRoute,
        selects smartSet: SmartModSet,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var presentation = ModManagerViewPresentation(sheet: .activity)
        var selectedLibraryItemID = ModLibrarySelection.defaultID
        var selectedModIDs: Set<String> = ["selected-mod"]

        let result = makeDispatcher().dispatch(
            route,
            presentation: &presentation,
            selectedLibraryItemID: &selectedLibraryItemID,
            selectedModIDs: &selectedModIDs
        )

        XCTAssertEqual(result, .handled, file: file, line: line)
        XCTAssertNil(presentation.sheet, file: file, line: line)
        XCTAssertEqual(
            selectedLibraryItemID,
            ModLibrarySelection.smartID(smartSet),
            file: file,
            line: line
        )
        XCTAssertTrue(selectedModIDs.isEmpty, file: file, line: line)
    }

    private func makeDispatcher() -> SeedBoxRouteDispatcher {
        SeedBoxRouteDispatcher(state: makeState())
    }

    private func makeState() -> ModManagerState {
        let defaultSet = ModSet(
            id: ModSetStore.defaultSetID,
            name: ModSetStore.defaultSetName,
            disabledFolderNames: [],
            isDefault: true,
            isIncluded: false
        )
        let favoritesSet = ModSet(
            id: "favorites",
            name: "Favorites",
            disabledFolderNames: [],
            isDefault: false,
            isIncluded: false
        )
        return ModManagerState(
            modsDirectoryPath: "/tmp/SeedBoxTests/Stardew Valley/Contents/MacOS/Mods",
            status: InstallationStatus(
                modDirectoryExists: true,
                issues: []
            ),
            hasSavedFolderAccess: true,
            mods: [visibleMod, hiddenFromWarningsMod],
            invalidModFolders: [],
            archivedMods: [],
            archiveSummary: ModArchiveSummary(),
            archiveSettings: ArchiveSettings(
                automaticallyPrunesExpiredArchives: false,
                retentionDays: ArchiveSettings.defaultRetentionDays
            ),
            hasLoadedMods: true,
            modSets: [defaultSet, favoritesSet],
            userSmartModSets: [
                UserSmartModSet(
                    id: "visible",
                    name: "Visible Mods",
                    searchText: "Visible"
                )
            ],
            selectedModSetID: ModSetStore.defaultSetID,
            appliedModSetID: ModSetStore.defaultSetID,
            activityStatus: nil,
            auditTrail: AuditTrailState(
                logPath: "/tmp/SeedBoxTests/Audit Log.json",
                recentEntries: [],
                lastErrorMessage: nil
            ),
            pendingSourceCleanupOffer: nil
        )
    }
}
