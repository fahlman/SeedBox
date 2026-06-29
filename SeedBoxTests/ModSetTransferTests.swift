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
}
