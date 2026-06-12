import XCTest
@testable import SeedBox

@MainActor
final class ModManagerViewModelTests: SeedBoxTestCase {
    func testSelectingModSetAppliesStoredModStates() async throws {
        let install = try makeInstall()
        let consoleCommandsURL = install.modDirectoryURL.appendingPathComponent("ConsoleCommands")
        let saveBackupURL = install.modDirectoryURL.appendingPathComponent("SaveBackup")
        let defaults = try makeIsolatedUserDefaults()

        try FileManager.default.createDirectory(at: consoleCommandsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: saveBackupURL, withIntermediateDirectories: true)
        try writeManifest(name: "Console Commands", to: consoleCommandsURL)
        try writeManifest(name: "Save Backup", to: saveBackupURL)

        let viewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )
        await viewModel.chooseModsFolder(install.modDirectoryURL)

        XCTAssertEqual(viewModel.state.readiness, .ready)
        XCTAssertEqual(viewModel.state.modSetSelection.selectedSetID, ModSetStore.defaultSetID)
        XCTAssertTrue(viewModel.state.modSetSelection.selectedSetIsApplied)
        XCTAssertEqual(modEnabledStates(in: viewModel.state.mods), [
            "Console Commands": true,
            "Save Backup": true
        ])

        await viewModel.createModSet(named: "All Disabled")
        let allDisabledSetID = viewModel.state.selectedModSetID
        XCTAssertEqual(viewModel.state.modSetSelection.selectedSet?.name, "All Disabled")
        XCTAssertTrue(viewModel.state.modSetSelection.selectedSetIsApplied)

        let consoleCommands = try XCTUnwrap(
            viewModel.state.mods.first { $0.displayName == "Console Commands" }
        )
        await viewModel.setMod(consoleCommands, enabled: false)

        let saveBackup = try XCTUnwrap(
            viewModel.state.mods.first { $0.displayName == "Save Backup" }
        )
        await viewModel.setMod(saveBackup, enabled: false)

        XCTAssertEqual(modEnabledStates(in: viewModel.state.mods), [
            "Console Commands": false,
            "Save Backup": false
        ])
        XCTAssertEqual(viewModel.state.modSetSelection.appliedSetID, allDisabledSetID)

        await viewModel.selectModSet(id: ModSetStore.defaultSetID)
        XCTAssertEqual(modEnabledStates(in: viewModel.state.mods), [
            "Console Commands": true,
            "Save Backup": true
        ])
        XCTAssertTrue(viewModel.state.modSetSelection.selectedSetIsApplied)

        await viewModel.selectModSet(id: allDisabledSetID)
        XCTAssertEqual(modEnabledStates(in: viewModel.state.mods), [
            "Console Commands": false,
            "Save Backup": false
        ])
        XCTAssertEqual(viewModel.state.modSetSelection.appliedSetID, allDisabledSetID)
    }

    func testIncludedDefaultSetDoesNotSaveManualChangesInRealTime() async throws {
        let install = try makeInstall()
        let consoleCommandsURL = install.modDirectoryURL.appendingPathComponent("ConsoleCommands")
        let defaults = try makeIsolatedUserDefaults()

        try FileManager.default.createDirectory(at: consoleCommandsURL, withIntermediateDirectories: true)
        try writeManifest(name: "Console Commands", to: consoleCommandsURL)

        let viewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )
        await viewModel.chooseModsFolder(install.modDirectoryURL)
        XCTAssertTrue(viewModel.state.modSetSelection.selectedSetIsApplied)
        XCTAssertFalse(viewModel.state.modSetSelection.selectedSetCanBeRenamed)
        XCTAssertFalse(viewModel.state.modSetSelection.selectedSetCanBeDeleted)

        let consoleCommands = try XCTUnwrap(
            viewModel.state.mods.first { $0.displayName == "Console Commands" }
        )
        await viewModel.setMod(consoleCommands, enabled: false)

        XCTAssertNil(viewModel.state.modSetSelection.appliedSetID)
        XCTAssertFalse(viewModel.state.modSetSelection.selectedSetIsApplied)
        XCTAssertEqual(modEnabledStates(in: viewModel.state.mods), [
            "Console Commands": false
        ])

        let reloadedSets = try ModSetStore.loadSets(
            install: install,
            currentMods: viewModel.state.mods
        )
        let defaultSet = try XCTUnwrap(reloadedSets.first(where: \.isDefault))
        XCTAssertEqual(defaultSet.disabledFolderNames, [])

        await viewModel.selectModSet(id: ModSetStore.defaultSetID)
        XCTAssertEqual(viewModel.state.modSetSelection.appliedSetID, ModSetStore.defaultSetID)
        XCTAssertTrue(viewModel.state.modSetSelection.selectedSetIsApplied)
        XCTAssertEqual(modEnabledStates(in: viewModel.state.mods), [
            "Console Commands": true
        ])

        let restoredViewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )
        await restoredViewModel.refresh()
        XCTAssertEqual(restoredViewModel.state.modSetSelection.appliedSetID, ModSetStore.defaultSetID)
        XCTAssertTrue(restoredViewModel.state.modSetSelection.selectedSetIsApplied)
        XCTAssertEqual(modEnabledStates(in: restoredViewModel.state.mods), [
            "Console Commands": true
        ])
    }

    func testSelectingIncludedAllAndNoneSetsAppliesGeneratedStates() async throws {
        let install = try makeInstall()
        let consoleCommandsURL = install.modDirectoryURL.appendingPathComponent("ConsoleCommands")
        let saveBackupURL = install.modDirectoryURL.appendingPathComponent(".SaveBackup")
        let defaults = try makeIsolatedUserDefaults()

        try FileManager.default.createDirectory(at: consoleCommandsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: saveBackupURL, withIntermediateDirectories: true)
        try writeManifest(name: "Console Commands", to: consoleCommandsURL)
        try writeManifest(name: "Save Backup", to: saveBackupURL)

        let viewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )
        await viewModel.chooseModsFolder(install.modDirectoryURL)

        await viewModel.selectModSet(id: ModSetStore.noneSetID)
        XCTAssertEqual(viewModel.state.modSetSelection.appliedSetID, ModSetStore.noneSetID)
        XCTAssertFalse(viewModel.state.modSetSelection.selectedSetCanBeRenamed)
        XCTAssertFalse(viewModel.state.modSetSelection.selectedSetCanBeDeleted)
        XCTAssertEqual(modEnabledStates(in: viewModel.state.mods), [
            "Console Commands": false,
            "Save Backup": false
        ])

        await viewModel.selectModSet(id: ModSetStore.allSetID)
        XCTAssertEqual(viewModel.state.modSetSelection.appliedSetID, ModSetStore.allSetID)
        XCTAssertFalse(viewModel.state.modSetSelection.selectedSetCanBeRenamed)
        XCTAssertFalse(viewModel.state.modSetSelection.selectedSetCanBeDeleted)
        XCTAssertEqual(modEnabledStates(in: viewModel.state.mods), [
            "Console Commands": true,
            "Save Backup": true
        ])
    }

    func testAddingModToCustomSetInstallsEnabledAndSavesSet() async throws {
        let install = try makeInstall()
        let consoleCommandsURL = install.modDirectoryURL.appendingPathComponent("ConsoleCommands")
        let newModSourceURL = temporaryDirectory
            .appendingPathComponent("Downloads")
            .appendingPathComponent("NewMod")
        let defaults = try makeIsolatedUserDefaults()

        try FileManager.default.createDirectory(at: consoleCommandsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newModSourceURL, withIntermediateDirectories: true)
        try writeManifest(name: "Console Commands", to: consoleCommandsURL)
        try writeManifest(name: "New Mod", to: newModSourceURL)

        let viewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )
        await viewModel.chooseModsFolder(install.modDirectoryURL)
        await viewModel.createModSet(named: "Favorites")
        let favoritesSetID = viewModel.state.selectedModSetID

        let consoleCommands = try XCTUnwrap(
            viewModel.state.mods.first { $0.displayName == "Console Commands" }
        )
        await viewModel.setMod(consoleCommands, enabled: false)
        await viewModel.addMods(from: [newModSourceURL])

        XCTAssertEqual(viewModel.state.modSetSelection.appliedSetID, favoritesSetID)
        XCTAssertEqual(modEnabledStates(in: viewModel.state.mods), [
            "Console Commands": false,
            "New Mod": true
        ])
        XCTAssertEqual(
            viewModel.state.pendingSourceCleanupOffer?.sourceURLs.map(\.path),
            [newModSourceURL.path]
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: install.modDirectoryURL
                    .appendingPathComponent("NewMod")
                    .appendingPathComponent("manifest.json")
                    .path
            )
        )

        let reloadedSets = try ModSetStore.loadSets(
            install: install,
            currentMods: viewModel.state.mods
        )
        let favoritesSet = try XCTUnwrap(reloadedSets.first { $0.id == favoritesSetID })
        XCTAssertEqual(favoritesSet.disabledFolderNames, ["ConsoleCommands"])
    }

    func testDismissingSourceCleanupOfferKeepsOriginalFile() async throws {
        let install = try makeInstall()
        let sourceURL = temporaryDirectory
            .appendingPathComponent("Downloads")
            .appendingPathComponent("NewMod")
        let defaults = try makeIsolatedUserDefaults()

        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try writeManifest(name: "New Mod", to: sourceURL)

        let viewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )
        await viewModel.chooseModsFolder(install.modDirectoryURL)
        await viewModel.addMods(from: [sourceURL])

        let offer = try XCTUnwrap(viewModel.state.pendingSourceCleanupOffer)
        XCTAssertEqual(offer.sourceURLs.map(\.path), [sourceURL.path])

        await viewModel.dismissSourceCleanupOffer()

        XCTAssertNil(viewModel.state.pendingSourceCleanupOffer)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: sourceURL.appendingPathComponent("manifest.json").path
            )
        )
    }

    func testRememberingKeepFilesSuppressesFutureCleanupNotifications() async throws {
        let install = try makeInstall()
        let sourceURL = temporaryDirectory
            .appendingPathComponent("Downloads")
            .appendingPathComponent("NewMod")
        let defaults = try makeIsolatedUserDefaults()

        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try writeManifest(name: "New Mod", to: sourceURL)

        let viewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )
        await viewModel.chooseModsFolder(install.modDirectoryURL)
        await viewModel.addMods(from: [sourceURL])

        let offer = try XCTUnwrap(viewModel.state.pendingSourceCleanupOffer)
        await viewModel.keepSourceFiles(for: offer, remembersChoice: true)

        let preferences = ModManagerPreferences(defaults: defaults)
        XCTAssertFalse(preferences.moveModFilesToTrashAfterAddingMods)
        XCTAssertTrue(preferences.suppressAddModsSuccessNotification)
        XCTAssertNil(viewModel.state.pendingSourceCleanupOffer)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: sourceURL.appendingPathComponent("manifest.json").path
            )
        )
    }

    func testSuppressedSourceCleanupNotificationKeepsOriginalsWhenMovePreferenceIsOff() async throws {
        let install = try makeInstall()
        let sourceURL = temporaryDirectory
            .appendingPathComponent("Downloads")
            .appendingPathComponent("NewMod")
        let defaults = try makeIsolatedUserDefaults()
        var preferences = ModManagerPreferences(defaults: defaults)
        preferences.moveModFilesToTrashAfterAddingMods = false
        preferences.suppressAddModsSuccessNotification = true

        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try writeManifest(name: "New Mod", to: sourceURL)

        let viewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )
        await viewModel.chooseModsFolder(install.modDirectoryURL)
        await viewModel.addMods(from: [sourceURL])

        XCTAssertNil(viewModel.state.pendingSourceCleanupOffer)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: sourceURL.appendingPathComponent("manifest.json").path
            )
        )
    }

    func testMovePreferenceTrashesOriginalsWithoutPromptWhenNotificationIsSuppressed() async throws {
        let install = try makeInstall()
        let sourceURL = temporaryDirectory
            .appendingPathComponent("Downloads")
            .appendingPathComponent("NewMod")
        let defaults = try makeIsolatedUserDefaults()
        var preferences = ModManagerPreferences(defaults: defaults)
        preferences.moveModFilesToTrashAfterAddingMods = true
        preferences.suppressAddModsSuccessNotification = true

        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try writeManifest(name: "New Mod", to: sourceURL)

        let viewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )
        await viewModel.chooseModsFolder(install.modDirectoryURL)
        await viewModel.addMods(from: [sourceURL])

        XCTAssertNil(viewModel.state.pendingSourceCleanupOffer)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
        let trashedEntry = try XCTUnwrap(viewModel.state.auditTrail.recentEntries.last)
        XCTAssertEqual(trashedEntry.action, .sourceFilesMovedToTrash)
    }

    func testAddingModToAppliedNoneSetInstallsDisabledAndKeepsNoneApplied() async throws {
        let install = try makeInstall()
        let consoleCommandsURL = install.modDirectoryURL.appendingPathComponent("ConsoleCommands")
        let newModSourceURL = temporaryDirectory
            .appendingPathComponent("Downloads")
            .appendingPathComponent("NewMod")
        let defaults = try makeIsolatedUserDefaults()

        try FileManager.default.createDirectory(at: consoleCommandsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newModSourceURL, withIntermediateDirectories: true)
        try writeManifest(name: "Console Commands", to: consoleCommandsURL)
        try writeManifest(name: "New Mod", to: newModSourceURL)

        let viewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )
        await viewModel.chooseModsFolder(install.modDirectoryURL)
        await viewModel.selectModSet(id: ModSetStore.noneSetID)
        await viewModel.addMods(from: [newModSourceURL])

        XCTAssertEqual(viewModel.state.modSetSelection.appliedSetID, ModSetStore.noneSetID)
        XCTAssertEqual(modEnabledStates(in: viewModel.state.mods), [
            "Console Commands": false,
            "New Mod": false
        ])
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: install.modDirectoryURL
                    .appendingPathComponent(".NewMod")
                    .appendingPathComponent("manifest.json")
                    .path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: install.modDirectoryURL.appendingPathComponent("NewMod").path
            )
        )

        let noneSet = try XCTUnwrap(viewModel.state.modSets.first { $0.id == ModSetStore.noneSetID })
        XCTAssertEqual(noneSet.disabledFolderNames, ["ConsoleCommands", "NewMod"])
    }

    func testAddingAlreadyInstalledModReportsSkippedInstall() async throws {
        let install = try makeInstall()
        let existingURL = install.modDirectoryURL.appendingPathComponent("ContentPatcher")
        let sourceURL = temporaryDirectory
            .appendingPathComponent("Downloads")
            .appendingPathComponent("ContentPatcher")
        let defaults = try makeIsolatedUserDefaults()

        try FileManager.default.createDirectory(at: existingURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try writeManifest(
            name: "Content Patcher",
            to: existingURL,
            version: "1.2.0",
            uniqueID: "Pathoschild.ContentPatcher"
        )
        try writeManifest(
            name: "Content Patcher",
            to: sourceURL,
            version: "1.2.0",
            uniqueID: "Pathoschild.ContentPatcher"
        )

        let viewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )
        await viewModel.chooseModsFolder(install.modDirectoryURL)
        await viewModel.addMods(from: [sourceURL])

        XCTAssertEqual(viewModel.state.statusLineMessage, "Content Patcher is already installed.")
        XCTAssertNil(viewModel.state.pendingSourceCleanupOffer)
        XCTAssertEqual(modEnabledStates(in: viewModel.state.mods), [
            "Content Patcher": true
        ])
        let skippedEntry = try XCTUnwrap(viewModel.state.auditTrail.recentEntries.last)
        XCTAssertEqual(skippedEntry.action, .modsInstallSkipped)
        XCTAssertEqual(skippedEntry.details["skipped_count"], "1")
        XCTAssertEqual(skippedEntry.details["skipped_mods"], "Content Patcher: already_installed")
    }

    func testAddingNewerInstalledModUpdatesAndArchivesPreviousCopy() async throws {
        let install = try makeInstall()
        let existingURL = install.modDirectoryURL.appendingPathComponent("ContentPatcher")
        let sourceURL = temporaryDirectory
            .appendingPathComponent("Downloads")
            .appendingPathComponent("ContentPatcher")
        let defaults = try makeIsolatedUserDefaults()

        try FileManager.default.createDirectory(at: existingURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try writeManifest(
            name: "Content Patcher",
            to: existingURL,
            version: "1.2.0",
            uniqueID: "Pathoschild.ContentPatcher"
        )
        try writeManifest(
            name: "Content Patcher",
            to: sourceURL,
            version: "1.10.0",
            uniqueID: "Pathoschild.ContentPatcher"
        )

        let viewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )
        await viewModel.chooseModsFolder(install.modDirectoryURL)
        await viewModel.addMods(from: [sourceURL])

        let updatedMod = try XCTUnwrap(viewModel.state.mods.first { $0.displayName == "Content Patcher" })
        XCTAssertEqual(updatedMod.versionText, "1.10.0")
        XCTAssertEqual(
            viewModel.state.statusLineMessage,
            "Updated Content Patcher from 1.2.0 to 1.10.0. Archived previous copy."
        )
        XCTAssertEqual(
            viewModel.state.pendingSourceCleanupOffer?.sourceURLs.map(\.path),
            [sourceURL.path]
        )
        let updatedEntry = try XCTUnwrap(viewModel.state.auditTrail.recentEntries.last)
        XCTAssertEqual(updatedEntry.action, .modsUpdated)
        XCTAssertEqual(updatedEntry.details["updated_count"], "1")
        let archivedPath = try XCTUnwrap(updatedEntry.details["archive_paths"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: archivedPath))
    }

    func testDeletingModArchivesRestorableCopy() async throws {
        let install = try makeInstall()
        let modURL = install.modDirectoryURL.appendingPathComponent("ContentPatcher")
        let defaults = try makeIsolatedUserDefaults()

        try FileManager.default.createDirectory(at: modURL, withIntermediateDirectories: true)
        try writeManifest(name: "Content Patcher", to: modURL)

        let viewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )
        await viewModel.chooseModsFolder(install.modDirectoryURL)

        let mod = try XCTUnwrap(viewModel.state.mods.first { $0.displayName == "Content Patcher" })
        await viewModel.deleteMod(mod)

        XCTAssertTrue(viewModel.state.mods.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: modURL.path))
        XCTAssertEqual(
            viewModel.state.statusLineMessage,
            "Deleted Content Patcher. Archived a restorable copy."
        )
        let deletedEntry = try XCTUnwrap(viewModel.state.auditTrail.recentEntries.last)
        XCTAssertEqual(deletedEntry.action, .modDeleted)
        let archivedPath = try XCTUnwrap(deletedEntry.details["archive_path"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: archivedPath))
    }

    func testBulkDisablingAndEnablingModsUpdatesStatesWithSingleSummary() async throws {
        let install = try makeInstall()
        let defaults = try makeIsolatedUserDefaults()
        let modNames = ["Console Commands", "Content Patcher", "Save Backup"]

        for modName in modNames {
            let modURL = install.modDirectoryURL
                .appendingPathComponent(modName.replacingOccurrences(of: " ", with: ""))
            try FileManager.default.createDirectory(at: modURL, withIntermediateDirectories: true)
            try writeManifest(name: modName, to: modURL)
        }

        let viewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )
        await viewModel.chooseModsFolder(install.modDirectoryURL)
        let auditEntryCountBeforeDisable = viewModel.state.auditTrail.recentEntries.count

        await viewModel.setMods(viewModel.state.mods, enabled: false)

        XCTAssertEqual(modEnabledStates(in: viewModel.state.mods), [
            "Console Commands": false,
            "Content Patcher": false,
            "Save Backup": false
        ])
        XCTAssertEqual(viewModel.state.statusLineMessage, "Disabled 3 mods.")
        XCTAssertEqual(
            viewModel.state.auditTrail.recentEntries.count,
            auditEntryCountBeforeDisable + 1
        )
        let disabledEntry = try XCTUnwrap(viewModel.state.auditTrail.recentEntries.last)
        XCTAssertEqual(disabledEntry.action, .modDisabled)
        XCTAssertEqual(disabledEntry.subjects.count, 3)

        await viewModel.setMods(viewModel.state.mods, enabled: true)

        XCTAssertEqual(modEnabledStates(in: viewModel.state.mods), [
            "Console Commands": true,
            "Content Patcher": true,
            "Save Backup": true
        ])
        XCTAssertEqual(viewModel.state.statusLineMessage, "Enabled 3 mods.")
        let enabledEntry = try XCTUnwrap(viewModel.state.auditTrail.recentEntries.last)
        XCTAssertEqual(enabledEntry.action, .modEnabled)
        XCTAssertEqual(enabledEntry.subjects.count, 3)
    }

    func testFlagsEnabledModsRequiringNewerSMAPI() async throws {
        let install = try makeInstall()
        let defaults = try makeIsolatedUserDefaults()

        let bundledURL = install.modDirectoryURL.appendingPathComponent("ConsoleCommands")
        try FileManager.default.createDirectory(at: bundledURL, withIntermediateDirectories: true)
        try writeManifest(
            name: "Console Commands",
            to: bundledURL,
            version: "4.0.0",
            uniqueID: "SMAPI.ConsoleCommands"
        )

        let demandingURL = install.modDirectoryURL.appendingPathComponent("Demanding")
        try FileManager.default.createDirectory(at: demandingURL, withIntermediateDirectories: true)
        try """
        {"Name": "Demanding Mod", "Author": "Test", "Version": "1.0.0", \
        "UniqueID": "Test.Demanding", "MinimumApiVersion": "9.0.0"}
        """.write(
            to: demandingURL.appendingPathComponent("manifest.json"),
            atomically: true,
            encoding: .utf8
        )

        let viewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )
        await viewModel.chooseModsFolder(install.modDirectoryURL)

        XCTAssertEqual(viewModel.state.smapiVersionIssues.map(\.displayName), ["Demanding Mod"])
        XCTAssertTrue(viewModel.state.hasProblems)

        let demandingMod = try XCTUnwrap(
            viewModel.state.mods.first { $0.displayName == "Demanding Mod" }
        )
        await viewModel.setMod(demandingMod, enabled: false)

        XCTAssertTrue(viewModel.state.smapiVersionIssues.isEmpty, "Disabled mods aren't flagged.")
    }

    func testResolvingDuplicateGroupKeepsNewestCopyAndArchivesRest() async throws {
        let install = try makeInstall()
        let defaults = try makeIsolatedUserDefaults()
        let newerURL = install.modDirectoryURL.appendingPathComponent("Alpha")
        let olderURL = install.modDirectoryURL.appendingPathComponent("AlphaOld")

        try FileManager.default.createDirectory(at: newerURL, withIntermediateDirectories: true)
        try writeManifest(name: "Alpha", to: newerURL, version: "2.0.0", uniqueID: "Test.Alpha")
        try FileManager.default.createDirectory(at: olderURL, withIntermediateDirectories: true)
        try writeManifest(name: "Alpha", to: olderURL, version: "1.0.0", uniqueID: "Test.Alpha")

        let viewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )
        await viewModel.chooseModsFolder(install.modDirectoryURL)

        let group = try XCTUnwrap(viewModel.state.duplicateGroups.first)
        XCTAssertEqual(group.mods.count, 2)

        await viewModel.resolveDuplicateGroup(id: group.id)

        XCTAssertTrue(viewModel.state.duplicateGroups.isEmpty)
        XCTAssertEqual(viewModel.state.mods.map(\.folderName), ["Alpha"])
        XCTAssertEqual(viewModel.state.mods.first?.versionText, "2.0.0")
        XCTAssertFalse(FileManager.default.fileExists(atPath: olderURL.path))
        XCTAssertEqual(viewModel.state.archivedMods.count, 1)
        XCTAssertEqual(viewModel.state.archivedMods.first?.versionText, "1.0.0")

        let auditEntry = try XCTUnwrap(viewModel.state.auditTrail.recentEntries.last)
        XCTAssertEqual(auditEntry.action, .duplicatesResolved)
        XCTAssertEqual(auditEntry.details["kept_folder"], "Alpha")
        XCTAssertEqual(auditEntry.details["kept_version"], "2.0.0")
    }

    func testFailedModSetCreationRecordsErrorSeverityStatus() async throws {
        let install = try makeInstall()
        let modURL = install.modDirectoryURL.appendingPathComponent("ContentPatcher")
        let defaults = try makeIsolatedUserDefaults()

        try FileManager.default.createDirectory(at: modURL, withIntermediateDirectories: true)
        try writeManifest(name: "Content Patcher", to: modURL)

        let viewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )
        await viewModel.chooseModsFolder(install.modDirectoryURL)

        await viewModel.createModSet(named: "Favorites")
        XCTAssertEqual(viewModel.state.statusLineSeverity, .info)

        await viewModel.createModSet(named: "Favorites")

        XCTAssertEqual(viewModel.state.activityStatus?.severity, .error)
        XCTAssertEqual(viewModel.state.statusLineSeverity, .error)
    }

    func testRestoringDeletedModFromHistoryRestoresFolderAndAudits() async throws {
        let install = try makeInstall()
        let modURL = install.modDirectoryURL.appendingPathComponent("ContentPatcher")
        let defaults = try makeIsolatedUserDefaults()

        try FileManager.default.createDirectory(at: modURL, withIntermediateDirectories: true)
        try writeManifest(name: "Content Patcher", to: modURL, version: "1.0.0")
        let archivedURL = try ModArchive.archive(
            modURL,
            in: install.archivedModsDirectoryURL,
            reason: .deleted
        )

        let viewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )
        await viewModel.chooseModsFolder(install.modDirectoryURL)

        XCTAssertTrue(viewModel.state.mods.isEmpty)
        XCTAssertEqual(viewModel.state.archiveSummary.archivedModCount, 1)

        let archivedMod = try XCTUnwrap(viewModel.state.archivedMods.first)
        await viewModel.restoreArchivedMods([archivedMod])

        XCTAssertEqual(viewModel.state.mods.map(\.displayName), ["Content Patcher"])
        XCTAssertEqual(viewModel.state.archiveSummary.archivedModCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: archivedURL.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: install.modDirectoryURL
                    .appendingPathComponent("ContentPatcher")
                    .appendingPathComponent("manifest.json")
                    .path
            )
        )

        let restoredEntry = try XCTUnwrap(viewModel.state.auditTrail.recentEntries.last)
        XCTAssertEqual(restoredEntry.action, .modRestored)
        XCTAssertEqual(restoredEntry.details["restored_count"], "1")
    }

    func testStartupScanAddsClosedAppModToLastAppliedCustomSet() async throws {
        let install = try makeInstall()
        let consoleCommandsURL = install.modDirectoryURL.appendingPathComponent("ConsoleCommands")
        let disabledNewModURL = install.modDirectoryURL.appendingPathComponent(".NewMod")
        let defaults = try makeIsolatedUserDefaults()

        try FileManager.default.createDirectory(at: consoleCommandsURL, withIntermediateDirectories: true)
        try writeManifest(name: "Console Commands", to: consoleCommandsURL)

        let viewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )
        await viewModel.chooseModsFolder(install.modDirectoryURL)
        await viewModel.createModSet(named: "Favorites")
        let favoritesSetID = viewModel.state.selectedModSetID

        let consoleCommands = try XCTUnwrap(
            viewModel.state.mods.first { $0.displayName == "Console Commands" }
        )
        await viewModel.setMod(consoleCommands, enabled: false)

        try FileManager.default.createDirectory(at: disabledNewModURL, withIntermediateDirectories: true)
        try writeManifest(name: "New Mod", to: disabledNewModURL)

        let restoredViewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL,
            selectedModSetID: favoritesSetID
        )
        await restoredViewModel.refresh()

        XCTAssertEqual(restoredViewModel.state.modSetSelection.appliedSetID, favoritesSetID)
        XCTAssertEqual(modEnabledStates(in: restoredViewModel.state.mods), [
            "Console Commands": false,
            "New Mod": true
        ])
        XCTAssertFalse(FileManager.default.fileExists(atPath: disabledNewModURL.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: install.modDirectoryURL
                    .appendingPathComponent("NewMod")
                    .appendingPathComponent("manifest.json")
                    .path
            )
        )

        let favoritesSet = try XCTUnwrap(
            restoredViewModel.state.modSets.first { $0.id == favoritesSetID }
        )
        XCTAssertEqual(favoritesSet.disabledFolderNames, ["ConsoleCommands"])

        let addedEntry = try XCTUnwrap(restoredViewModel.state.auditTrail.recentEntries.last)
        XCTAssertEqual(addedEntry.action, .modsAdded)
        XCTAssertEqual(addedEntry.details["source"], "startup_scan")
        XCTAssertEqual(addedEntry.details["installed_state"], "enabled")
    }

    func testStartupScanDisablesClosedAppModWhenNoneSetWasApplied() async throws {
        let install = try makeInstall()
        let consoleCommandsURL = install.modDirectoryURL.appendingPathComponent("ConsoleCommands")
        let enabledNewModURL = install.modDirectoryURL.appendingPathComponent("NewMod")
        let defaults = try makeIsolatedUserDefaults()

        try FileManager.default.createDirectory(at: consoleCommandsURL, withIntermediateDirectories: true)
        try writeManifest(name: "Console Commands", to: consoleCommandsURL)

        let viewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )
        await viewModel.chooseModsFolder(install.modDirectoryURL)
        await viewModel.selectModSet(id: ModSetStore.noneSetID)

        try FileManager.default.createDirectory(at: enabledNewModURL, withIntermediateDirectories: true)
        try writeManifest(name: "New Mod", to: enabledNewModURL)

        let restoredViewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL,
            selectedModSetID: ModSetStore.noneSetID
        )
        await restoredViewModel.refresh()

        XCTAssertEqual(restoredViewModel.state.modSetSelection.appliedSetID, ModSetStore.noneSetID)
        XCTAssertEqual(modEnabledStates(in: restoredViewModel.state.mods), [
            "Console Commands": false,
            "New Mod": false
        ])
        XCTAssertFalse(FileManager.default.fileExists(atPath: enabledNewModURL.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: install.modDirectoryURL
                    .appendingPathComponent(".NewMod")
                    .appendingPathComponent("manifest.json")
                    .path
            )
        )

        let noneSet = try XCTUnwrap(
            restoredViewModel.state.modSets.first { $0.id == ModSetStore.noneSetID }
        )
        XCTAssertEqual(noneSet.disabledFolderNames, ["ConsoleCommands", "NewMod"])

        let addedEntry = try XCTUnwrap(restoredViewModel.state.auditTrail.recentEntries.last)
        XCTAssertEqual(addedEntry.action, .modsAdded)
        XCTAssertEqual(addedEntry.details["source"], "startup_scan")
        XCTAssertEqual(addedEntry.details["installed_state"], "disabled")
    }

    func testDeletingSelectedModSetAppliesDefaultSet() async throws {
        let install = try makeInstall()
        let consoleCommandsURL = install.modDirectoryURL.appendingPathComponent("ConsoleCommands")
        let saveBackupURL = install.modDirectoryURL.appendingPathComponent("SaveBackup")
        let defaults = try makeIsolatedUserDefaults()

        try FileManager.default.createDirectory(at: consoleCommandsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: saveBackupURL, withIntermediateDirectories: true)
        try writeManifest(name: "Console Commands", to: consoleCommandsURL)
        try writeManifest(name: "Save Backup", to: saveBackupURL)

        let viewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )
        await viewModel.chooseModsFolder(install.modDirectoryURL)
        await viewModel.createModSet(named: "All Disabled")

        let allDisabledSet = try XCTUnwrap(viewModel.state.modSetSelection.selectedSet)
        for mod in viewModel.state.mods {
            await viewModel.setMod(mod, enabled: false)
        }

        XCTAssertEqual(modEnabledStates(in: viewModel.state.mods), [
            "Console Commands": false,
            "Save Backup": false
        ])

        await viewModel.deleteModSet(allDisabledSet)

        XCTAssertEqual(viewModel.state.selectedModSetID, ModSetStore.defaultSetID)
        XCTAssertFalse(viewModel.state.modSets.contains { $0.id == allDisabledSet.id })
        XCTAssertEqual(modEnabledStates(in: viewModel.state.mods), [
            "Console Commands": true,
            "Save Backup": true
        ])
        XCTAssertTrue(viewModel.state.modSetSelection.selectedSetIsApplied)
    }

    func testRestoresPersistedFolderAndStoredSelectedModSet() async throws {
        let install = try makeInstall()
        let consoleCommandsURL = install.modDirectoryURL.appendingPathComponent("ConsoleCommands")
        let defaults = try makeIsolatedUserDefaults()

        try FileManager.default.createDirectory(at: consoleCommandsURL, withIntermediateDirectories: true)
        try writeManifest(name: "Console Commands", to: consoleCommandsURL)

        let viewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )
        await viewModel.chooseModsFolder(install.modDirectoryURL)
        await viewModel.createModSet(named: "Custom")

        let selectedSetID = viewModel.state.selectedModSetID
        let preferences = ModManagerPreferences(defaults: defaults)
        XCTAssertEqual(preferences.modsDirectoryPath, install.modDirectoryURL.path)

        let restoredViewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL,
            selectedModSetID: selectedSetID
        )

        XCTAssertEqual(restoredViewModel.state.modsDirectoryPath, install.modDirectoryURL.path)
        XCTAssertEqual(restoredViewModel.state.selectedModSetID, selectedSetID)

        let freshViewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )
        XCTAssertEqual(freshViewModel.state.selectedModSetID, ModSetStore.defaultSetID)
    }

    func testAuditTrailRecordsModAndModSetActions() async throws {
        let install = try makeInstall()
        let consoleCommandsURL = install.modDirectoryURL.appendingPathComponent("ConsoleCommands")
        let newModSourceURL = temporaryDirectory
            .appendingPathComponent("Downloads")
            .appendingPathComponent("NewMod")
        let defaults = try makeIsolatedUserDefaults()

        try FileManager.default.createDirectory(at: consoleCommandsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newModSourceURL, withIntermediateDirectories: true)
        try writeManifest(name: "Console Commands", to: consoleCommandsURL)
        try writeManifest(name: "New Mod", to: newModSourceURL)

        let viewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )
        await viewModel.chooseModsFolder(install.modDirectoryURL)
        await viewModel.createModSet(named: "Favorites")
        await viewModel.renameSelectedModSet(to: "Keepers")
        await viewModel.addMods(from: [newModSourceURL])

        let newMod = try XCTUnwrap(viewModel.state.mods.first { $0.displayName == "New Mod" })
        await viewModel.setMod(newMod, enabled: false)

        let keepersSet = try XCTUnwrap(viewModel.state.modSetSelection.selectedSet)
        await viewModel.deleteModSet(keepersSet)

        let entries = try AuditLogStore.loadEntries(from: install.auditLogURL)
        XCTAssertEqual(viewModel.state.auditTrail.logPath, install.auditLogURL.path)
        XCTAssertNil(viewModel.state.auditTrail.lastErrorMessage)
        XCTAssertEqual(viewModel.state.auditTrail.recentEntries, entries)
        XCTAssertEqual(entries.map(\.action), [
            .modsFolderSelected,
            .modSetCreated,
            .modSetRenamed,
            .modsAdded,
            .modDisabled,
            .modSetDeleted
        ])

        let addedEntry = try XCTUnwrap(entries.first { $0.action == .modsAdded })
        XCTAssertEqual(addedEntry.subjects.map(\.name), ["New Mod"])
        XCTAssertEqual(addedEntry.details["installed_state"], "enabled")

        let renamedEntry = try XCTUnwrap(entries.first { $0.action == .modSetRenamed })
        XCTAssertEqual(renamedEntry.details["old_name"], "Favorites")
        XCTAssertEqual(renamedEntry.details["new_name"], "Keepers")
        XCTAssertEqual(viewModel.state.activityMessage, "")
        XCTAssertEqual(viewModel.state.statusLineMessage, entries.last?.summary)
    }

    func testAuditTrailReloadsFromPersistentLog() async throws {
        let install = try makeInstall()
        let consoleCommandsURL = install.modDirectoryURL.appendingPathComponent("ConsoleCommands")
        let defaults = try makeIsolatedUserDefaults()

        try FileManager.default.createDirectory(at: consoleCommandsURL, withIntermediateDirectories: true)
        try writeManifest(name: "Console Commands", to: consoleCommandsURL)

        let viewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )
        await viewModel.chooseModsFolder(install.modDirectoryURL)
        await viewModel.createModSet(named: "Favorites")

        let persistedEntries = try AuditLogStore.loadEntries(from: install.auditLogURL)
        XCTAssertEqual(persistedEntries.map(\.action), [
            .modsFolderSelected,
            .modSetCreated
        ])

        let restoredViewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )
        await restoredViewModel.refresh()

        XCTAssertEqual(restoredViewModel.state.auditTrail.logPath, install.auditLogURL.path)
        XCTAssertEqual(restoredViewModel.state.auditTrail.recentEntries, persistedEntries)
        XCTAssertNil(restoredViewModel.state.auditTrail.lastErrorMessage)
    }

    func testObservedFolderChangeRefreshesModsAndShowsNotification() async throws {
        let install = try makeInstall()
        let consoleCommandsURL = install.modDirectoryURL.appendingPathComponent("ConsoleCommands")
        let saveBackupURL = install.modDirectoryURL.appendingPathComponent("SaveBackup")
        let defaults = try makeIsolatedUserDefaults()
        let monitor = SpyModsFolderMonitor()
        let notifier = SpyModFolderChangeNotifier()

        try FileManager.default.createDirectory(at: consoleCommandsURL, withIntermediateDirectories: true)
        try writeManifest(name: "Console Commands", to: consoleCommandsURL)

        let viewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL,
            modsFolderMonitor: monitor,
            folderChangeNotifier: notifier
        )
        await viewModel.chooseModsFolder(install.modDirectoryURL)

        XCTAssertEqual(monitor.watchedPath, install.modDirectoryURL.standardizedFileURL.resolvingSymlinksInPath().path)
        XCTAssertEqual(modEnabledStates(in: viewModel.state.mods), [
            "Console Commands": true
        ])

        try FileManager.default.createDirectory(at: saveBackupURL, withIntermediateDirectories: true)
        try writeManifest(name: "Save Backup", to: saveBackupURL)

        monitor.simulateChange()
        try await waitUntil {
            viewModel.state.mods.contains { $0.displayName == "Save Backup" }
        }

        XCTAssertEqual(modEnabledStates(in: viewModel.state.mods), [
            "Console Commands": true,
            "Save Backup": true
        ])
        let noneSet = try XCTUnwrap(viewModel.state.modSets.first { $0.id == ModSetStore.noneSetID })
        XCTAssertEqual(noneSet.disabledFolderNames, ["ConsoleCommands", "SaveBackup"])
        XCTAssertEqual(viewModel.state.statusLineMessage, "Added 1 mod folder.")
        let addedEntry = try XCTUnwrap(viewModel.state.auditTrail.recentEntries.last)
        XCTAssertEqual(addedEntry.action, .modsAdded)
        XCTAssertEqual(addedEntry.details["source"], "watched_folder")
        XCTAssertEqual(addedEntry.details["installed_state"], "enabled")
        XCTAssertEqual(notifier.notificationCount, 1)
    }

    func testObservedAddedModIsEnabledAndSavedIntoCustomSet() async throws {
        let install = try makeInstall()
        let consoleCommandsURL = install.modDirectoryURL.appendingPathComponent("ConsoleCommands")
        let disabledNewModURL = install.modDirectoryURL.appendingPathComponent(".NewMod")
        let defaults = try makeIsolatedUserDefaults()

        try FileManager.default.createDirectory(at: consoleCommandsURL, withIntermediateDirectories: true)
        try writeManifest(name: "Console Commands", to: consoleCommandsURL)

        let viewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )
        await viewModel.chooseModsFolder(install.modDirectoryURL)
        await viewModel.createModSet(named: "Favorites")
        let favoritesSetID = viewModel.state.selectedModSetID

        let consoleCommands = try XCTUnwrap(
            viewModel.state.mods.first { $0.displayName == "Console Commands" }
        )
        await viewModel.setMod(consoleCommands, enabled: false)

        try FileManager.default.createDirectory(at: disabledNewModURL, withIntermediateDirectories: true)
        try writeManifest(name: "New Mod", to: disabledNewModURL)

        let service = makeService(defaults: defaults, install: install, initialState: viewModel.state)
        let (reconciledState, didObserveExternalChange) = await service.reconcileObservedModsFolderChange()

        XCTAssertTrue(didObserveExternalChange)
        XCTAssertEqual(reconciledState.modSetSelection.appliedSetID, favoritesSetID)
        XCTAssertEqual(modEnabledStates(in: reconciledState.mods), [
            "Console Commands": false,
            "New Mod": true
        ])
        XCTAssertFalse(FileManager.default.fileExists(atPath: disabledNewModURL.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: install.modDirectoryURL
                    .appendingPathComponent("NewMod")
                    .appendingPathComponent("manifest.json")
                    .path
            )
        )

        let favoritesSet = try XCTUnwrap(reconciledState.modSets.first { $0.id == favoritesSetID })
        XCTAssertEqual(favoritesSet.disabledFolderNames, ["ConsoleCommands"])

        let addedEntry = try XCTUnwrap(reconciledState.auditTrail.recentEntries.last)
        XCTAssertEqual(addedEntry.action, .modsAdded)
        XCTAssertEqual(addedEntry.details["source"], "watched_folder")
        XCTAssertEqual(addedEntry.details["installed_state"], "enabled")
    }

    func testObservedAddedModIsDisabledWhenNoneSetIsApplied() async throws {
        let install = try makeInstall()
        let consoleCommandsURL = install.modDirectoryURL.appendingPathComponent("ConsoleCommands")
        let enabledNewModURL = install.modDirectoryURL.appendingPathComponent("NewMod")
        let defaults = try makeIsolatedUserDefaults()

        try FileManager.default.createDirectory(at: consoleCommandsURL, withIntermediateDirectories: true)
        try writeManifest(name: "Console Commands", to: consoleCommandsURL)

        let viewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )
        await viewModel.chooseModsFolder(install.modDirectoryURL)
        await viewModel.selectModSet(id: ModSetStore.noneSetID)

        try FileManager.default.createDirectory(at: enabledNewModURL, withIntermediateDirectories: true)
        try writeManifest(name: "New Mod", to: enabledNewModURL)

        let service = makeService(defaults: defaults, install: install, initialState: viewModel.state)
        let (reconciledState, didObserveExternalChange) = await service.reconcileObservedModsFolderChange()

        XCTAssertTrue(didObserveExternalChange)
        XCTAssertEqual(reconciledState.modSetSelection.appliedSetID, ModSetStore.noneSetID)
        XCTAssertEqual(modEnabledStates(in: reconciledState.mods), [
            "Console Commands": false,
            "New Mod": false
        ])
        XCTAssertFalse(FileManager.default.fileExists(atPath: enabledNewModURL.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: install.modDirectoryURL
                    .appendingPathComponent(".NewMod")
                    .appendingPathComponent("manifest.json")
                    .path
            )
        )

        let noneSet = try XCTUnwrap(reconciledState.modSets.first { $0.id == ModSetStore.noneSetID })
        XCTAssertEqual(noneSet.disabledFolderNames, ["ConsoleCommands", "NewMod"])

        let addedEntry = try XCTUnwrap(reconciledState.auditTrail.recentEntries.last)
        XCTAssertEqual(addedEntry.action, .modsAdded)
        XCTAssertEqual(addedEntry.details["source"], "watched_folder")
        XCTAssertEqual(addedEntry.details["installed_state"], "disabled")
    }

    func testAppInitiatedFolderChangeDoesNotShowFolderChangeNotification() async throws {
        let install = try makeInstall()
        let consoleCommandsURL = install.modDirectoryURL.appendingPathComponent("ConsoleCommands")
        let defaults = try makeIsolatedUserDefaults()
        let monitor = SpyModsFolderMonitor()
        let notifier = SpyModFolderChangeNotifier()

        try FileManager.default.createDirectory(at: consoleCommandsURL, withIntermediateDirectories: true)
        try writeManifest(name: "Console Commands", to: consoleCommandsURL)

        let viewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL,
            modsFolderMonitor: monitor,
            folderChangeNotifier: notifier
        )
        await viewModel.chooseModsFolder(install.modDirectoryURL)

        let consoleCommands = try XCTUnwrap(
            viewModel.state.mods.first { $0.displayName == "Console Commands" }
        )
        await viewModel.setMod(consoleCommands, enabled: false)

        monitor.simulateChange()
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(notifier.notificationCount, 0)
    }

    private func makeService(
        defaults: UserDefaults,
        install: StardewInstall,
        initialState: ModManagerState
    ) -> ModManagerService {
        let folderAccess = SecurityScopedFolderAccess(defaults: defaults)
        let stateStore = ModManagerStateStore(
            folderAccess: folderAccess,
            modSetDirectory: install.modSetDirectoryURL,
            preferences: ModManagerPreferences(defaults: defaults)
        )
        return ModManagerService(
            folderAccess: folderAccess,
            smapiLogFolderAccess: SecurityScopedFolderAccess(
                defaults: defaults,
                bookmarkKey: "smapiLogFolderBookmarkData"
            ),
            stateStore: stateStore,
            initialState: initialState,
            modSetDirectory: install.modSetDirectoryURL
        )
    }

}

private final class SpyModsFolderMonitor: ModsFolderMonitoring {
    var onChange: (@MainActor () -> Void)?
    private(set) var watchedPath: String?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func startWatching(_ url: URL, securityScopedAccess: SecurityScopedAccessToken) throws {
        watchedPath = url.standardizedFileURL.resolvingSymlinksInPath().path
        startCount += 1
        securityScopedAccess.stop()
    }

    func stopWatching() {
        watchedPath = nil
        stopCount += 1
    }

    @MainActor
    func simulateChange() {
        onChange?()
    }
}

private final class SpyModFolderChangeNotifier: ModFolderChangeNotifying {
    private(set) var authorizationRequestCount = 0
    private(set) var notificationCount = 0

    func requestAuthorization() {
        authorizationRequestCount += 1
    }

    func notifyModsFolderChanged() {
        notificationCount += 1
    }
}
