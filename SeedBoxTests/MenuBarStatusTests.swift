import XCTest
@testable import SeedBox

final class MenuBarStatusTests: SeedBoxTestCase {
    func testReportsNoFolderAccess() throws {
        let state = try makeState(hasFolderAccess: false)
        let status = MenuBarStatus.make(from: state)
        XCTAssertFalse(status.hasFolderAccess)
    }

    func testReportsSelectedSetAndZeroCountsForCleanState() throws {
        let set = ModSet(id: ModSetStore.defaultSetID, name: "Default", disabledFolderNames: [])
        let state = try makeState(hasFolderAccess: true, modSets: [set])

        let status = MenuBarStatus.make(from: state)

        XCTAssertTrue(status.hasFolderAccess)
        XCTAssertEqual(status.selectedSetName, "Default")
        XCTAssertEqual(status.warningsCount, 0)
        XCTAssertEqual(status.errorsCount, 0)
        XCTAssertEqual(status.updatesCount, 0)
        XCTAssertFalse(status.hasWarnings)
        XCTAssertFalse(status.hasErrors)
        XCTAssertFalse(status.hasLastSessionIssues)
    }

    func testUpdatesCountIsZeroWhenUpdateChecksAreOff() throws {
        let mod = ModInfo(
            folderName: "ContentPatcher",
            url: URL(fileURLWithPath: "/tmp/ContentPatcher"),
            isEnabled: true,
            manifest: ModManifest(
                name: "Content Patcher",
                author: "Author",
                version: "1.0.0",
                description: nil,
                uniqueID: "Pathoschild.ContentPatcher",
                entryDll: nil,
                minimumApiVersion: nil,
                updateKeys: nil,
                contentPackFor: nil,
                dependencies: nil
            )
        )
        let update = ModAvailableUpdate(
            modID: "pathoschild.contentpatcher",
            displayName: "Content Patcher",
            installedVersion: "1.0.0",
            latestVersion: "2.0.0",
            downloadURL: nil
        )
        let state = try makeState(
            hasFolderAccess: true,
            mods: [mod],
            availableUpdates: [update],
            checksForModUpdates: false
        )

        XCTAssertEqual(MenuBarStatus.make(from: state).updatesCount, 0)
    }

    private func makeState(
        hasFolderAccess: Bool,
        mods: [ModInfo] = [],
        modSets: [ModSet] = [],
        availableUpdates: [ModAvailableUpdate] = [],
        checksForModUpdates: Bool = false
    ) throws -> ModManagerState {
        let install = try makeInstall()
        return ModManagerState(
            modsDirectoryPath: install.modDirectoryURL.path,
            status: install.status(),
            hasSavedFolderAccess: hasFolderAccess,
            mods: mods,
            invalidModFolders: [],
            archivedMods: [],
            archiveSummary: ModArchiveSummary(),
            archiveSettings: ArchiveSettings(
                automaticallyPrunesExpiredArchives: false,
                retentionDays: ArchiveSettings.defaultRetentionDays
            ),
            checksForModUpdates: checksForModUpdates,
            availableUpdates: availableUpdates,
            hasLoadedMods: true,
            modSets: modSets,
            selectedModSetID: ModSetStore.defaultSetID,
            appliedModSetID: nil,
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
