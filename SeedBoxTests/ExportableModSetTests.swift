import XCTest
@testable import SeedBox

final class ExportableModSetTests: SeedBoxTestCase {
    func testMakeProducesShareableSeedBoxSetData() throws {
        let install = try makeInstall()
        try makeInstalledMod(name: "Content Patcher", in: install, folderName: "ContentPatcher")
        let mods = try ModLibrary.scan(install: install)
        let set = ModSet(id: "favorites", name: "Favorites", disabledFolderNames: ["ContentPatcher"])

        let exportable = try XCTUnwrap(ExportableModSet.make(for: set, mods: mods, in: [set]))

        XCTAssertEqual(exportable.name, "Favorites")
        XCTAssertEqual(exportable.suggestedFileName, "Favorites.seedboxset")

        // The shared bytes are a valid, reproducible .seedboxset export.
        let decoded = try SeedBoxSetCodec.decode(exportable.data)
        XCTAssertEqual(decoded.modSet.name, "Favorites")
        XCTAssertEqual(decoded.modSet.disabledMods.map(\.folderName), ["ContentPatcher"])
    }

    func testSuggestedFileNameSanitizesIllegalCharacters() throws {
        let exportable = ExportableModSet(name: "Co-op / Winter: 2026", data: Data())
        XCTAssertEqual(exportable.suggestedFileName, "Co-op - Winter- 2026.seedboxset")
    }

    func testSuggestedFileNameFallsBackForEmptyName() throws {
        let exportable = ExportableModSet(name: "   ", data: Data())
        XCTAssertEqual(exportable.suggestedFileName, "Mod Set.seedboxset")
    }
}
