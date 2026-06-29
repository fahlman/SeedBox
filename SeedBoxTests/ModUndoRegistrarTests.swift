import XCTest
@testable import SeedBox

@MainActor
final class ModUndoRegistrarTests: SeedBoxTestCase {
    func testUndoRestoresPreviousModStateAndEnablesRedo() async throws {
        let install = try makeInstall()
        let defaults = try makeIsolatedUserDefaults()
        try makeInstalledMod(name: "Content Patcher", in: install, folderName: "ContentPatcher")
        let viewModel = await makeReadyViewModel(for: install, defaults: defaults)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false

        let mod = try XCTUnwrap(viewModel.state.mods.first { $0.displayName == "Content Patcher" })
        XCTAssertTrue(mod.isEnabled)

        // Perform the disable and register its undo, as the view does. The
        // app relies on the run loop to close undo groups; tests close it
        // explicitly so there is something to undo.
        await viewModel.setMod(mod, enabled: false)
        undoManager.beginUndoGrouping()
        ModUndoRegistrar.registerModToggle(
            in: undoManager,
            viewModel: viewModel,
            modID: mod.id,
            restoringTo: true,
            appliedValue: false
        )
        undoManager.endUndoGrouping()
        XCTAssertTrue(undoManager.canUndo)
        XCTAssertEqual(installedState(of: "Content Patcher", in: viewModel), false)

        // Undo re-enables the mod and a redo becomes available.
        undoManager.undo()
        try await waitUntil { installedState(of: "Content Patcher", in: viewModel) == true }
        XCTAssertTrue(undoManager.canRedo)

        // Redo disables it again.
        undoManager.redo()
        try await waitUntil { installedState(of: "Content Patcher", in: viewModel) == false }
        XCTAssertTrue(undoManager.canUndo)
    }

    func testUndoIsSkippedWhenModChangedSinceTheAction() async throws {
        let install = try makeInstall()
        let defaults = try makeIsolatedUserDefaults()
        try makeInstalledMod(name: "Automate", in: install, folderName: "Automate")
        let viewModel = await makeReadyViewModel(for: install, defaults: defaults)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false

        let mod = try XCTUnwrap(viewModel.state.mods.first { $0.displayName == "Automate" })

        // Disable, then register undo restoring to enabled.
        await viewModel.setMod(mod, enabled: false)
        undoManager.beginUndoGrouping()
        ModUndoRegistrar.registerModToggle(
            in: undoManager,
            viewModel: viewModel,
            modID: mod.id,
            restoringTo: true,
            appliedValue: false
        )
        undoManager.endUndoGrouping()

        // The user re-enables it manually before undoing.
        let disabledMod = try XCTUnwrap(viewModel.state.mods.first { $0.displayName == "Automate" })
        await viewModel.setMod(disabledMod, enabled: true)
        XCTAssertEqual(installedState(of: "Automate", in: viewModel), true)

        // Undo must not clobber the newer state; the mod stays enabled.
        undoManager.undo()
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(installedState(of: "Automate", in: viewModel), true)
        XCTAssertFalse(undoManager.canRedo)
    }

    func testUndoApplyModSetReappliesPreviousSet() async throws {
        let install = try makeInstall()
        let defaults = try makeIsolatedUserDefaults()
        try makeInstalledMod(name: "Content Patcher", in: install, folderName: "ContentPatcher")
        let viewModel = await makeReadyViewModel(for: install, defaults: defaults)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false

        // Two distinct sets: "All" (nothing disabled) and "None" (all disabled).
        let startSetID = viewModel.state.selectedModSetID
        await viewModel.selectModSet(id: ModSetStore.noneSetID)
        XCTAssertEqual(viewModel.state.selectedModSetID, ModSetStore.noneSetID)
        XCTAssertEqual(installedState(of: "Content Patcher", in: viewModel), false)

        await viewModel.selectModSet(id: ModSetStore.allSetID)
        XCTAssertEqual(installedState(of: "Content Patcher", in: viewModel), true)
        undoManager.beginUndoGrouping()
        ModUndoRegistrar.registerModSetApply(
            in: undoManager,
            viewModel: viewModel,
            previousSetID: ModSetStore.noneSetID,
            appliedSetID: ModSetStore.allSetID
        )
        undoManager.endUndoGrouping()

        // Undo re-applies the "None" set, disabling the mod again.
        undoManager.undo()
        try await waitUntil { viewModel.state.selectedModSetID == ModSetStore.noneSetID }
        XCTAssertEqual(installedState(of: "Content Patcher", in: viewModel), false)
        XCTAssertTrue(undoManager.canRedo)

        // Redo re-applies "All".
        undoManager.redo()
        try await waitUntil { viewModel.state.selectedModSetID == ModSetStore.allSetID }
        XCTAssertEqual(installedState(of: "Content Patcher", in: viewModel), true)

        _ = startSetID
    }

    private func installedState(of displayName: String, in viewModel: ModManagerViewModel) -> Bool? {
        viewModel.state.mods.first { $0.displayName == displayName }?.isEnabled
    }
}
