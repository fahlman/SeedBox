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
        XCTAssertEqual(modEnabledStates(in: viewModel.mods), [
            "Console Commands": true,
            "Save Backup": true
        ])

        await viewModel.createModSet(named: "All Disabled")
        let allDisabledSetID = viewModel.selectedModSetID
        XCTAssertEqual(viewModel.state.modSetSelection.selectedSet?.name, "All Disabled")
        XCTAssertTrue(viewModel.state.modSetSelection.selectedSetIsApplied)

        let consoleCommands = try XCTUnwrap(
            viewModel.mods.first { $0.displayName == "Console Commands" }
        )
        await viewModel.setMod(consoleCommands, enabled: false)

        let saveBackup = try XCTUnwrap(
            viewModel.mods.first { $0.displayName == "Save Backup" }
        )
        await viewModel.setMod(saveBackup, enabled: false)

        XCTAssertEqual(modEnabledStates(in: viewModel.mods), [
            "Console Commands": false,
            "Save Backup": false
        ])
        XCTAssertEqual(viewModel.state.modSetSelection.appliedSetID, allDisabledSetID)

        await viewModel.selectModSet(id: ModSetStore.defaultSetID)
        XCTAssertEqual(modEnabledStates(in: viewModel.mods), [
            "Console Commands": true,
            "Save Backup": true
        ])
        XCTAssertTrue(viewModel.state.modSetSelection.selectedSetIsApplied)

        await viewModel.selectModSet(id: allDisabledSetID)
        XCTAssertEqual(modEnabledStates(in: viewModel.mods), [
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
            viewModel.mods.first { $0.displayName == "Console Commands" }
        )
        await viewModel.setMod(consoleCommands, enabled: false)

        XCTAssertNil(viewModel.state.modSetSelection.appliedSetID)
        XCTAssertFalse(viewModel.state.modSetSelection.selectedSetIsApplied)
        XCTAssertEqual(modEnabledStates(in: viewModel.mods), [
            "Console Commands": false
        ])

        let reloadedSets = try ModSetStore.loadSets(
            install: install,
            currentMods: viewModel.mods
        )
        let defaultSet = try XCTUnwrap(reloadedSets.first(where: \.isDefault))
        XCTAssertEqual(defaultSet.disabledFolderNames, [])

        await viewModel.selectModSet(id: ModSetStore.defaultSetID)
        XCTAssertEqual(viewModel.state.modSetSelection.appliedSetID, ModSetStore.defaultSetID)
        XCTAssertTrue(viewModel.state.modSetSelection.selectedSetIsApplied)
        XCTAssertEqual(modEnabledStates(in: viewModel.mods), [
            "Console Commands": true
        ])

        let restoredViewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )
        await restoredViewModel.refresh()
        XCTAssertEqual(restoredViewModel.state.modSetSelection.appliedSetID, ModSetStore.defaultSetID)
        XCTAssertTrue(restoredViewModel.state.modSetSelection.selectedSetIsApplied)
        XCTAssertEqual(modEnabledStates(in: restoredViewModel.mods), [
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
        XCTAssertEqual(modEnabledStates(in: viewModel.mods), [
            "Console Commands": false,
            "Save Backup": false
        ])

        await viewModel.selectModSet(id: ModSetStore.allSetID)
        XCTAssertEqual(viewModel.state.modSetSelection.appliedSetID, ModSetStore.allSetID)
        XCTAssertFalse(viewModel.state.modSetSelection.selectedSetCanBeRenamed)
        XCTAssertFalse(viewModel.state.modSetSelection.selectedSetCanBeDeleted)
        XCTAssertEqual(modEnabledStates(in: viewModel.mods), [
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
        let favoritesSetID = viewModel.selectedModSetID

        let consoleCommands = try XCTUnwrap(
            viewModel.mods.first { $0.displayName == "Console Commands" }
        )
        await viewModel.setMod(consoleCommands, enabled: false)
        await viewModel.addMods(from: [newModSourceURL])

        XCTAssertEqual(viewModel.state.modSetSelection.appliedSetID, favoritesSetID)
        XCTAssertEqual(modEnabledStates(in: viewModel.mods), [
            "Console Commands": false,
            "New Mod": true
        ])
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
            currentMods: viewModel.mods
        )
        let favoritesSet = try XCTUnwrap(reloadedSets.first { $0.id == favoritesSetID })
        XCTAssertEqual(favoritesSet.disabledFolderNames, ["ConsoleCommands"])
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
        XCTAssertEqual(modEnabledStates(in: viewModel.mods), [
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
        let favoritesSetID = viewModel.selectedModSetID

        let consoleCommands = try XCTUnwrap(
            viewModel.mods.first { $0.displayName == "Console Commands" }
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
        XCTAssertEqual(modEnabledStates(in: restoredViewModel.mods), [
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
        XCTAssertEqual(modEnabledStates(in: restoredViewModel.mods), [
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
        for mod in viewModel.mods {
            await viewModel.setMod(mod, enabled: false)
        }

        XCTAssertEqual(modEnabledStates(in: viewModel.mods), [
            "Console Commands": false,
            "Save Backup": false
        ])

        await viewModel.deleteModSet(allDisabledSet)

        XCTAssertEqual(viewModel.selectedModSetID, ModSetStore.defaultSetID)
        XCTAssertFalse(viewModel.state.modSets.contains { $0.id == allDisabledSet.id })
        XCTAssertEqual(modEnabledStates(in: viewModel.mods), [
            "Console Commands": true,
            "Save Backup": true
        ])
        XCTAssertTrue(viewModel.state.modSetSelection.selectedSetIsApplied)
    }

    func testRestoresPersistedFolderAndWindowSelectedModSet() async throws {
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

        let selectedSetID = viewModel.selectedModSetID
        let preferences = ModManagerPreferences(defaults: defaults)
        XCTAssertEqual(preferences.modsDirectoryPath, install.modDirectoryURL.path)

        let restoredViewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL,
            selectedModSetID: selectedSetID
        )

        XCTAssertEqual(restoredViewModel.state.modsDirectoryPath, install.modDirectoryURL.path)
        XCTAssertEqual(restoredViewModel.selectedModSetID, selectedSetID)

        let newWindowViewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )
        XCTAssertEqual(newWindowViewModel.selectedModSetID, ModSetStore.defaultSetID)
    }

    func testWindowsCanKeepDifferentSelectedModSets() async throws {
        let install = try makeInstall()
        let consoleCommandsURL = install.modDirectoryURL.appendingPathComponent("ConsoleCommands")
        let defaults = try makeIsolatedUserDefaults()

        try FileManager.default.createDirectory(at: consoleCommandsURL, withIntermediateDirectories: true)
        try writeManifest(name: "Console Commands", to: consoleCommandsURL)

        let firstWindow = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )
        let secondWindow = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )

        await firstWindow.chooseModsFolder(install.modDirectoryURL)
        await firstWindow.createModSet(named: "Favorites")
        let favoritesSetID = firstWindow.selectedModSetID

        secondWindow.restoreWindowSelectedModSet(id: ModSetStore.noneSetID)
        await secondWindow.refresh()

        XCTAssertEqual(firstWindow.selectedModSetID, favoritesSetID)
        XCTAssertEqual(secondWindow.selectedModSetID, ModSetStore.noneSetID)
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

        let newMod = try XCTUnwrap(viewModel.mods.first { $0.displayName == "New Mod" })
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
        XCTAssertEqual(addedEntry.subjects.map(\.name), ["NewMod"])
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
        XCTAssertEqual(modEnabledStates(in: viewModel.mods), [
            "Console Commands": true
        ])

        try FileManager.default.createDirectory(at: saveBackupURL, withIntermediateDirectories: true)
        try writeManifest(name: "Save Backup", to: saveBackupURL)

        monitor.simulateChange()
        try await waitUntil {
            viewModel.mods.contains { $0.displayName == "Save Backup" }
        }

        XCTAssertEqual(modEnabledStates(in: viewModel.mods), [
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
        let favoritesSetID = viewModel.selectedModSetID

        let consoleCommands = try XCTUnwrap(
            viewModel.mods.first { $0.displayName == "Console Commands" }
        )
        await viewModel.setMod(consoleCommands, enabled: false)

        try FileManager.default.createDirectory(at: disabledNewModURL, withIntermediateDirectories: true)
        try writeManifest(name: "New Mod", to: disabledNewModURL)

        let service = ModManagerService(
            folderAccess: SecurityScopedFolderAccess(defaults: defaults),
            modSetDirectory: install.modSetDirectoryURL
        )
        let reconciledState = await service.reconcileObservedModsFolderChange(from: viewModel.state)

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

        let service = ModManagerService(
            folderAccess: SecurityScopedFolderAccess(defaults: defaults),
            modSetDirectory: install.modSetDirectoryURL
        )
        let reconciledState = await service.reconcileObservedModsFolderChange(from: viewModel.state)

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
            viewModel.mods.first { $0.displayName == "Console Commands" }
        )
        await viewModel.setMod(consoleCommands, enabled: false)

        monitor.simulateChange()
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(notifier.notificationCount, 0)
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() {
                return
            }

            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTFail("Timed out waiting for condition.", file: file, line: line)
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
