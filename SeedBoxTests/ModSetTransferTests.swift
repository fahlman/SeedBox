import XCTest
@testable import SeedBox

final class ModSetTransferTests: SeedBoxTestCase {
    func testResolvedDisabledFolderNamesFlattensInheritance() throws {
        let base = ModSet(id: "base", name: "Base", disabledFolderNames: ["Alpha", "Bravo"])
        let child = ModSet(
            id: "child",
            name: "Child",
            disabledFolderNames: ["Charlie"],
            parentID: "base",
            enabledFolderNames: ["Alpha"]
        )

        let names = ModSetResolver.resolvedDisabledFolderNames(for: child, in: [base, child])

        // Inherited Bravo kept, inherited Alpha re-enabled, own Charlie added.
        XCTAssertEqual(names, ["Bravo", "Charlie"])
    }

    func testExportImportRoundTripThroughFile() throws {
        let install = try makeInstall()
        try makeInstalledMod(name: "Content Patcher", in: install, folderName: "ContentPatcher")
        try makeInstalledMod(name: "Automate", in: install, folderName: "Automate")
        let mods = try ModLibrary.scan(install: install)

        let set = ModSet(id: "favorites", name: "Favorites", disabledFolderNames: ["ContentPatcher"])
        let url = temporaryDirectory.appendingPathComponent("Favorites.seedboxset")

        try ModSetTransfer.write(set, mods: mods, in: [set], to: url)

        // Importing alongside an existing same-named set avoids the collision.
        let existing = [ModSet(id: "other", name: "Favorites", disabledFolderNames: [])]
        let imported = try ModSetTransfer.importModSet(fromFileAt: url, existingSets: existing)

        XCTAssertEqual(imported.name, "Favorites 2")
        XCTAssertEqual(imported.disabledFolderNames, ["ContentPatcher"])
        XCTAssertNotEqual(imported.id, set.id)
    }

    func testExportResolvesInheritedSetBeforeWriting() throws {
        let base = ModSet(id: "base", name: "Base", disabledFolderNames: ["ContentPatcher", "Automate"])
        let child = ModSet(
            id: "child",
            name: "Child",
            disabledFolderNames: [],
            parentID: "base",
            enabledFolderNames: ["Automate"]
        )

        let document = ModSetTransfer.exportDocument(for: child, mods: [], in: [base, child])

        // The exported (regular) set carries the resolved disabled list.
        XCTAssertEqual(document.modSet.disabledMods.map(\.folderName), ["ContentPatcher"])
    }

    func testImportFromMissingFileThrowsMalformed() throws {
        let url = temporaryDirectory.appendingPathComponent("does-not-exist.seedboxset")
        XCTAssertThrowsError(try ModSetTransfer.importModSet(fromFileAt: url, existingSets: [])) { error in
            XCTAssertEqual(error as? SeedBoxSetError, .malformedData)
        }
    }

    func testImportRejectsSymbolicLink() throws {
        let targetURL = temporaryDirectory.appendingPathComponent("Target.seedboxset")
        let linkURL = temporaryDirectory.appendingPathComponent("Link.seedboxset")
        let document = SeedBoxSetCodec.makeDocument(
            name: "Linked",
            disabledFolderNames: [],
            installedMods: []
        )
        try SeedBoxSetCodec.encode(document).write(to: targetURL)
        try FileManager.default.createSymbolicLink(
            at: linkURL,
            withDestinationURL: targetURL
        )

        XCTAssertThrowsError(
            try ModSetTransfer.importModSet(
                fromFileAt: linkURL,
                existingSets: []
            )
        ) { error in
            XCTAssertEqual(error as? SeedBoxSetError, .malformedData)
        }
    }

    @MainActor
    func testViewModelExportsAndImportsModSet() async throws {
        let install = try makeInstall()
        let defaults = try makeIsolatedUserDefaults()
        try makeInstalledMod(name: "Content Patcher", in: install, folderName: "ContentPatcher")
        let viewModel = await makeReadyViewModel(for: install, defaults: defaults)

        // Make a set that disables Content Patcher, then export it to a file.
        await viewModel.createModSet(named: "Travelers")
        let cp = try XCTUnwrap(viewModel.state.mods.first { $0.displayName == "Content Patcher" })
        await viewModel.setMod(cp, enabled: false)

        let exportable = try XCTUnwrap(viewModel.exportableSelectedModSet())
        let url = temporaryDirectory.appendingPathComponent("Travelers.seedboxset")
        try exportable.data.write(to: url)

        // Importing adds a new, non-colliding set selected but not applied.
        let beforeIDs = Set(viewModel.state.modSets.map(\.id))
        await viewModel.importModSet(fromFileAt: url)

        let newSet = try XCTUnwrap(viewModel.state.modSets.first { !beforeIDs.contains($0.id) })
        XCTAssertEqual(newSet.name, "Travelers 2")
        XCTAssertEqual(newSet.disabledFolderNames, ["ContentPatcher"])
        XCTAssertEqual(viewModel.state.selectedModSetID, newSet.id)
    }

    @MainActor
    func testViewModelCreatesExportableSelectedModSet() async throws {
        let install = try makeInstall()
        let defaults = try makeIsolatedUserDefaults()
        let viewModel = await makeReadyViewModel(for: install, defaults: defaults)
        await viewModel.createModSet(named: "Travelers")

        let exportable = try XCTUnwrap(viewModel.exportableSelectedModSet())
        let document = try SeedBoxSetCodec.decode(exportable.data)
        XCTAssertEqual(exportable.suggestedFileName, "Travelers.seedboxset")
        XCTAssertEqual(document.modSet.name, "Travelers")

        await viewModel.recordModSetExported(named: exportable.name)
        XCTAssertEqual(viewModel.state.activityMessage, "Exported mod set Travelers.")
    }
}
