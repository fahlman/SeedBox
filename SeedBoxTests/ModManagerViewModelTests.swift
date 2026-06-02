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

    func testDefaultSetSavesManualChangesInRealTime() async throws {
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

        let consoleCommands = try XCTUnwrap(
            viewModel.mods.first { $0.displayName == "Console Commands" }
        )
        await viewModel.setMod(consoleCommands, enabled: false)

        XCTAssertEqual(viewModel.state.modSetSelection.appliedSetID, ModSetStore.defaultSetID)
        XCTAssertEqual(modEnabledStates(in: viewModel.mods), [
            "Console Commands": false
        ])

        let reloadedSets = try ModSetStore.loadSets(
            install: install,
            currentMods: viewModel.mods
        )
        let defaultSet = try XCTUnwrap(reloadedSets.first(where: \.isDefault))
        XCTAssertEqual(defaultSet.disabledFolderNames, ["ConsoleCommands"])

        let restoredViewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )
        await restoredViewModel.refresh()
        XCTAssertEqual(restoredViewModel.state.modSetSelection.appliedSetID, ModSetStore.defaultSetID)
        XCTAssertTrue(restoredViewModel.state.modSetSelection.selectedSetIsApplied)
        XCTAssertEqual(modEnabledStates(in: restoredViewModel.mods), [
            "Console Commands": false
        ])
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

    func testRestoresPersistedFolderAndSelectedModSet() async throws {
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
        XCTAssertEqual(preferences.selectedModSetID, selectedSetID)

        let restoredViewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )

        XCTAssertEqual(restoredViewModel.state.modsDirectoryPath, install.modDirectoryURL.path)
        XCTAssertEqual(restoredViewModel.selectedModSetID, selectedSetID)
    }
}
