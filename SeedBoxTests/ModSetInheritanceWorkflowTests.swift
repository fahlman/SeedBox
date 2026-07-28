import XCTest
@testable import SeedBox

/// End-to-end coverage for creating and applying an inheriting Mod Set through
/// the view model, exercising the base-set wiring (#37) and resolved apply
/// (#39) together.
@MainActor
final class ModSetInheritanceWorkflowTests: SeedBoxTestCase {
    func testCreateInheritingSetStoresDeltaAndAppliesResolvedState() async throws {
        let install = try makeInstall()
        let defaults = try makeIsolatedUserDefaults()
        try makeInstalledMod(name: "Alpha", in: install, folderName: "Alpha")
        try makeInstalledMod(name: "Beta", in: install, folderName: "Beta")
        try makeInstalledMod(name: "Gamma", in: install, folderName: "Gamma")

        let viewModel = await makeReadyViewModel(for: install, defaults: defaults)

        // Create a standalone base set and have it disable Alpha.
        await viewModel.createModSet(named: "Base")
        let baseID = viewModel.state.selectedModSetID
        let alpha = try XCTUnwrap(viewModel.state.mods.first { $0.displayName == "Alpha" })
        await viewModel.setMod(alpha, enabled: false)

        // Create a child inheriting from the base. It currently matches the
        // base, so its stored delta is empty.
        await viewModel.createModSet(named: "Child", parentID: baseID)
        let childID = viewModel.state.selectedModSetID
        XCTAssertNotEqual(childID, baseID)

        var storedChild = try reloadSet(id: childID, install: install, mods: viewModel.state.mods)
        XCTAssertEqual(storedChild.parentID, baseID)
        XCTAssertEqual(storedChild.disabledFolderNames, [])
        XCTAssertEqual(storedChild.enabledFolderNames, [])

        // Disabling Beta while the child is selected records an extra disable as
        // a delta on top of the inherited Alpha disable.
        let beta = try XCTUnwrap(viewModel.state.mods.first { $0.displayName == "Beta" })
        await viewModel.setMod(beta, enabled: false)

        storedChild = try reloadSet(id: childID, install: install, mods: viewModel.state.mods)
        XCTAssertEqual(storedChild.parentID, baseID)
        XCTAssertEqual(storedChild.disabledFolderNames, ["Beta"])

        // Reverting Beta to the base (which leaves it enabled) drops the local
        // override, so the child once again matches the base.
        let disabledBeta = try XCTUnwrap(viewModel.state.mods.first { $0.displayName == "Beta" })
        await viewModel.setMod(disabledBeta, enabled: true)
        storedChild = try reloadSet(id: childID, install: install, mods: viewModel.state.mods)
        XCTAssertEqual(storedChild.disabledFolderNames, [])
        XCTAssertEqual(storedChild.parentID, baseID)

        // Re-disable Beta so the apply assertion below exercises an override.
        let enabledBeta = try XCTUnwrap(viewModel.state.mods.first { $0.displayName == "Beta" })
        await viewModel.setMod(enabledBeta, enabled: false)

        // Applying the child resolves the chain: Alpha (inherited) and Beta
        // (own) are disabled, Gamma stays enabled.
        await viewModel.selectModSet(id: baseID)
        await viewModel.selectModSet(id: childID)
        XCTAssertEqual(modEnabledStates(in: viewModel.state.mods), [
            "Alpha": false,
            "Beta": false,
            "Gamma": true
        ])
    }

    private func reloadSet(
        id: String,
        install: StardewInstall,
        mods: [ModInfo]
    ) throws -> ModSet {
        let sets = try ModSetStore.loadSets(install: install, currentMods: mods)
        return try XCTUnwrap(sets.first { $0.id == id })
    }
}
