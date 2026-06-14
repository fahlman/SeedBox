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

    func testSmartModSetFiltersContentPatcherPacksAndRegularMods() throws {
        let install = try makeInstall()
        let contentPatcherURL = install.modDirectoryURL.appendingPathComponent("ContentPatcher")
        let contentPackURL = install.modDirectoryURL.appendingPathComponent("FarmVisuals")

        try FileManager.default.createDirectory(at: contentPatcherURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: contentPackURL, withIntermediateDirectories: true)
        try writeManifest(
            name: "Content Patcher",
            to: contentPatcherURL,
            uniqueID: "Pathoschild.ContentPatcher"
        )
        try writeManifest(
            name: "Farm Visuals",
            to: contentPackURL,
            uniqueID: "Example.FarmVisuals",
            contentPackForUniqueID: "Pathoschild.ContentPatcher"
        )

        let mods = try ModLibrary.scan(install: install)
        let state = makeState(install: install, mods: mods)

        let contentPackState = ModManagerPresentationState(
            state: state,
            searchText: "",
            selectedModIDs: [],
            selectedLibraryItemID: ModLibrarySelection.smartID(.contentPatcherMods)
        )
        let regularModState = ModManagerPresentationState(
            state: state,
            searchText: "",
            selectedModIDs: [],
            selectedLibraryItemID: ModLibrarySelection.smartID(.smapiMods)
        )

        XCTAssertEqual(contentPackState.filteredMods.map(\.displayName), ["Farm Visuals"])
        XCTAssertEqual(regularModState.filteredMods.map(\.displayName), ["Content Patcher"])
    }

    func testSmartModSetFiltersUpdatesAvailable() throws {
        let install = try makeInstall()
        let updatedURL = install.modDirectoryURL.appendingPathComponent("UpdateMe")
        let currentURL = install.modDirectoryURL.appendingPathComponent("AlreadyCurrent")

        try FileManager.default.createDirectory(at: updatedURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: currentURL, withIntermediateDirectories: true)
        try writeManifest(
            name: "Update Me",
            to: updatedURL,
            version: "1.0.0",
            uniqueID: "Example.UpdateMe"
        )
        try writeManifest(
            name: "Already Current",
            to: currentURL,
            version: "1.0.0",
            uniqueID: "Example.AlreadyCurrent"
        )

        let mods = try ModLibrary.scan(install: install)
        var state = makeState(install: install, mods: mods)
        state.availableUpdates = [
            ModAvailableUpdate(
                modID: "Example.UpdateMe".normalizedDependencyID,
                displayName: "Update Me",
                installedVersion: "1.0.0",
                latestVersion: "2.0.0",
                downloadURL: nil
            ),
            ModAvailableUpdate(
                modID: "Example.AlreadyCurrent".normalizedDependencyID,
                displayName: "Already Current",
                installedVersion: "1.0.0",
                latestVersion: "1.0.0",
                downloadURL: nil
            )
        ]

        let presentationState = ModManagerPresentationState(
            state: state,
            searchText: "",
            selectedModIDs: [],
            selectedLibraryItemID: ModLibrarySelection.smartID(.updatesAvailable)
        )

        XCTAssertEqual(presentationState.filteredMods.map(\.displayName), ["Update Me"])
    }

    func testSmartModSetSelectionDisablesModSetCommands() throws {
        let install = try makeInstall()
        let modURL = install.modDirectoryURL.appendingPathComponent("SomeMod")

        try FileManager.default.createDirectory(at: modURL, withIntermediateDirectories: true)
        try writeManifest(name: "Some Mod", to: modURL)

        let mods = try ModLibrary.scan(install: install)
        let selectedUserSet = ModSetStore.snapshotSet(
            id: "favorites",
            name: "Favorites",
            from: mods,
            isDefault: false,
            isIncluded: false
        )
        var state = makeState(install: install, mods: mods, modSets: [selectedUserSet])
        state.selectedModSetID = selectedUserSet.id
        state.appliedModSetID = selectedUserSet.id

        let presentationState = ModManagerPresentationState(
            state: state,
            searchText: "",
            selectedModIDs: [],
            selectedLibraryItemID: ModLibrarySelection.smartID(.allMods)
        )

        XCTAssertNil(presentationState.selectedSet)
        XCTAssertNil(presentationState.selectedRenamableSet)
        XCTAssertNil(presentationState.selectedDeletableSet)
        XCTAssertFalse(ModManagerCommand.compareModSet.isEnabled(in: presentationState))
        XCTAssertFalse(ModManagerCommand.duplicateModSet.isEnabled(in: presentationState))
        XCTAssertFalse(ModManagerCommand.renameModSet.isEnabled(in: presentationState))
        XCTAssertFalse(ModManagerCommand.deleteModSet.isEnabled(in: presentationState))
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
            activityStatus: nil,
            auditTrail: AuditTrailState(
                logPath: install.modSetDirectory.appendingPathComponent("Audit Log.json").path,
                recentEntries: [],
                lastErrorMessage: nil
            ),
            pendingSourceCleanupOffer: nil
        )
    }
}
