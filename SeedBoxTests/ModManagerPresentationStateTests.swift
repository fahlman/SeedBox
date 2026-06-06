import XCTest
@testable import SeedBox

final class ModManagerPresentationStateTests: SeedBoxTestCase {
    func testFiltersAndSelectsModsUsingDependencyGraph() throws {
        let install = try makeInstall()
        let contentPatcherURL = install.modDirectoryURL.appendingPathComponent(".ContentPatcher")
        let expandedURL = install.modDirectoryURL.appendingPathComponent("StardewValleyExpanded")

        try FileManager.default.createDirectory(at: contentPatcherURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: expandedURL, withIntermediateDirectories: true)
        try writeManifest(
            name: "Content Patcher",
            to: contentPatcherURL,
            uniqueID: "Pathoschild.ContentPatcher"
        )
        try writeManifest(
            name: "Stardew Valley Expanded",
            to: expandedURL,
            uniqueID: "FlashShifter.StardewValleyExpandedCP",
            contentPackForUniqueID: "Pathoschild.ContentPatcher"
        )

        let mods = try ModLibrary.scan(install: install)
        let expandedMod = try XCTUnwrap(mods.first { $0.displayName == "Stardew Valley Expanded" })
        let state = makeState(install: install, mods: mods)
        let presentationState = ModManagerPresentationState(
            state: state,
            searchText: "dependency:disabled",
            selectedModIDs: [expandedMod.id]
        )

        XCTAssertEqual(presentationState.filteredMods.map(\.displayName), ["Stardew Valley Expanded"])
        XCTAssertEqual(presentationState.selection.mod?.displayName, "Stardew Valley Expanded")
        XCTAssertEqual(presentationState.selection.dependencyStatuses.map(\.displayName), ["Content Patcher"])
        XCTAssertTrue(presentationState.canManageMods)
        XCTAssertTrue(presentationState.canRevealSelectedMod)
        XCTAssertTrue(presentationState.canShowModInspector)
        XCTAssertTrue(presentationState.canShowProblems)
    }

    func testSelectionDerivedStateRequiresExactlyOneVisibleMod() throws {
        let install = try makeInstall()
        let firstURL = install.modDirectoryURL.appendingPathComponent("FirstMod")
        let secondURL = install.modDirectoryURL.appendingPathComponent("SecondMod")

        try FileManager.default.createDirectory(at: firstURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondURL, withIntermediateDirectories: true)
        try writeManifest(name: "First Mod", to: firstURL)
        try writeManifest(name: "Second Mod", to: secondURL)

        let mods = try ModLibrary.scan(install: install)
        let state = makeState(install: install, mods: mods)
        let presentationState = ModManagerPresentationState(
            state: state,
            searchText: "First",
            selectedModIDs: Set(mods.map(\.id))
        )

        XCTAssertEqual(presentationState.filteredMods.map(\.displayName), ["First Mod"])
        XCTAssertNil(presentationState.selection.mod)
        XCTAssertFalse(presentationState.canRevealSelectedMod)
        XCTAssertFalse(presentationState.canDeleteSelectedMod)
        XCTAssertFalse(presentationState.canShowModInspector)
    }

    private func makeState(
        install: StardewInstall,
        mods: [ModInfo],
        modSets: [ModSet]? = nil
    ) -> ModManagerState {
        let sets = modSets ?? [
            ModSetStore.snapshotSet(
                id: ModSetStore.defaultSetID,
                name: ModSetStore.defaultSetName,
                from: mods,
                isDefault: true,
                isIncluded: true
            )
        ]

        return ModManagerState(
            modsDirectoryPath: install.modDirectoryURL.path,
            status: install.status(),
            hasSavedFolderAccess: true,
            mods: mods,
            invalidModFolders: [],
            archivedMods: [],
            archiveSummary: ModArchiveSummary(),
            archiveSettings: ArchiveSettings(
                automaticallyPrunesExpiredArchives: false,
                retentionDays: ArchiveSettings.defaultRetentionDays
            ),
            hasLoadedMods: true,
            modSets: sets,
            selectedModSetID: ModSetStore.defaultSetID,
            appliedModSetID: ModSetStore.defaultSetID,
            activityMessage: "",
            auditTrail: AuditTrailState(
                logPath: install.modSetDirectory.appendingPathComponent("Audit Log.json").path,
                recentEntries: [],
                lastErrorMessage: nil
            ),
            pendingSourceCleanupOffer: nil
        )
    }
}
